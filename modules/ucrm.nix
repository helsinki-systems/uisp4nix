{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.ucrm;
  ucrm = pkgs.callPackage ../pkgs/ucrm.nix { };
  unms = pkgs.callPackage ../pkgs/unms.nix { };
in {
  options = {
    services.ucrm = {
      enable = mkEnableOption "Ubiquiti CRM";

      package = mkOption {
        default = ucrm.ucrmSrc;
        type = types.package;
        description = ''
          UISP server package to use.
        '';
      };

      postgres = {
        host = mkOption {
          default = "localhost";
          type = types.str;
          description = "
            Hostname or IP of the PostgreSQL server.
          ";
        };

        port = mkOption {
          default = 5432;
          type = types.port;
          description = "
            PostgreSQL server port.
          ";
        };

        db = mkOption {
          default = "unms";
          type = types.str;
          description = "
            PostgreSQL database in which to store UNMS data.
          ";
        };

        user = mkOption {
          default = "ucrm";
          type = types.str;
          description = "
            PostgreSQL server user.
          ";
        };

        passwordFile = mkOption {
          default = null;
          type = types.nullOr types.path;
          description = "
            File containing the PostgreSQL server password.
         ";
        };

        schema = mkOption {
          default = "ucrm";
          type = types.str;
          description = "
            PostgreSQL database schema.
          ";
        };
      };

      rabbitmq = {
        host = mkOption {
          default = "localhost";
          type = types.str;
          description = "
            Hostname or IP of the RabbitMQ server.
          ";
        };

        port = mkOption {
          default = 5672;
          type = types.port;
          description = "
            RabbitMQ server port.
          ";
        };
      };
    };
  };

  config = mkIf cfg.enable (let
    exportSecrets = ''
      export SECRET=$(cat /var/lib/secrets/ucrm/secret)
      export NODE_AUTH_KEY=$(cat /var/lib/secrets/ucrm/node_auth_key)
      export POSTGRES_PASSWORD=$(cat ${cfg.postgres.passwordFile})
      export PGPASSWORD="$POSTGRES_PASSWORD"
      export UNMS_TOKEN=$(cat /var/lib/secrets/unms/token)
    '';

    sharedAaRules = ''
      ${cfg.package}/vendor/symfony/cache/Adapter/** w,

      network tcp,
      deny network udp,
      deny network netlink raw,

      /var/lib/secrets/ucrm/* r,
      /var/lib/secrets/unms/* r,
    '';
  in {
    systemd.services.ucrm-init = {
      description = "Ubiquiti CRM";
      wantedBy = [ "multi-user.target" ];
      after = [ "postgresql.service" ];

      environment = {
        POSTGRES_DB = cfg.postgres.db;
        POSTGRES_PORT = toString cfg.postgres.port;
        POSTGRES_USER = cfg.postgres.user;
        POSTGRES_HOST = cfg.postgres.host;
        RABBITMQ_USER = "guest";
        RABBITMQ_PASSWORD = "guest";
        RABBITMQ_HOST = cfg.rabbitmq.host;
        RABBITMQ_PORT = toString cfg.rabbitmq.port;
        SYMFONY_ENV = "prod";
        SYMFONY_DEBUG = toString 0;
        POSTGRES_SCHEMA = cfg.postgres.schema;
        UNMS_POSTGRES_SCHEMA = config.services.uisp.postgres.schema;
        SUSPEND_PORT = "81";
        UNMS_HOST = "localhost";
        UNMS_PORT = toString config.services.uisp.httpPort;
        UNMS_VERSION = config.services.uisp.package.version;
      };

      path = with pkgs; [ config.services.postgresql.package which jq ucrm.phpEnv netcat ];

      preStart = ''
        set -eu
        export PATH=${cfg.package}/scripts/bin:$PATH
        ${exportSecrets}

        cat ${cfg.package}/app/config/parameters.yml.orig > /run/ucrm/parameters.yml
        ./scripts/parameters.sh
        for p in unms_stats_url sentry_dsn sentry_dsn_frontend; do
          sed -i "s#^    $p:.*#    $p: \"\"#" /run/ucrm/parameters.yml
        done
      '';

      script = ''
        set -eu
        ${exportSecrets}
        export PATH=${cfg.package}/scripts/bin:$PATH
        rm -rf /var/cache/ucrm/*
        # from the makefile
        ./scripts/migrate.sh

        # from scripts/web.sh
        ./app/console crm:uas:bump -v
        ./app/console crm:version:bump --save-to-database -v
        ./scripts/rabbitmq_ready.sh
        ./app/console rabbitmq:setup-fabric -v
        ./app/console crm:search:populate -v
        # ./app/console crm:suspension:setupStaticSuspensionPage -v
        ./app/console crm:plugin:symlink -v
        ./app/console crm:plugin:ucrm-config -v
        ./app/console crm:plugin:update-database-information -v
        ./app/console crm:migration:reset-in-progress-states -v
        ./app/console crm:migration:update-price-minus-tax -v
        ./app/console crm:migration:setup -v
        # ./app/console crm:unms:changes:sync -v
        ./app/console crm:unms:sync-site-relations -v
        ./app/console crm:unms:migrate-users -v
        ./app/console crm:unms:sync-users -v
        ./app/console crm:migration:set-sandbox -v
        ./app/console crm:unms:uimodel:sync -v
        ./app/console crm:service:status-update -v
        ./app/console crm:client:status-update -v
      '';

      serviceConfig = {
        User = "ucrm";
        Group = "ucrm";
        WorkingDirectory = cfg.package;
        LogsDirectory = "ucrm";
        CacheDirectory = "ucrm";
        RuntimeDirectory = "ucrm";
        RuntimeDirectoryMode = "700";
        RuntimeDirectoryPreserve = true;
        StateDirectory = [ "ucrm/uploads" "ucrm/data/ticketing/attachments" "ucrm/sessions" ];
        PrivateNetwork = false;
      };

      sandbox = 2;
      apparmor = {
        enable = true;
        extraConfig = sharedAaRules;
      };
    };

    systemd.services.ucrm-websockets = {
      sandbox = 2;

      apparmor = {
        enable = true;
        extraConfig = ''
          ${sharedAaRules}
          unix (create,getattr,getopt,setopt,shutdown),
          /run/ucrm/parameters.yml r,
        '';
      };

      wantedBy = [ "multi-user.target" ];

      script = ''
        ${exportSecrets}
        exec ${pkgs.nodejs}/bin/node ${cfg.package}/websockets/server.js
      '';

      serviceConfig = {
        User = "ucrm";
        Group = "ucrm";
        MemoryDenyWriteExecute = false;
        PrivateNetwork = false;
      };
    };

    helsinki.phpfpm.pools.ucrm = {
      user = "ucrm";
      apparmorPackages = [ cfg.package ];
      apparmor = ''
        network tcp,
        network udp,
        network netlink raw,
        # yes, this is in the store. it's used for locking. no, k doesn't work
        ${cfg.package}/vendor/symfony/cache/Adapter/** w,
      '';
      phpPackage = ucrm.phpEnv;
      settings = {
        "pm" = "dynamic";
        "pm.max_children" = 50;
        "pm.start_servers" = 5;
        "pm.min_spare_servers" = 5;
        "pm.max_spare_servers" = 10;
        "pm.max_requests" = 500;
        "catch_workers_output" = true;
      };
    };
    systemd.services."phpfpm-ucrm" = {
      serviceConfig = {
        CacheDirectory = "ucrm";
        StateDirectory = "ucrm";
        RuntimeDirectory = "ucrm";
        RuntimeDirectoryMode = "700";
        RuntimeDirectoryPreserve = true;
        PrivateNetwork = false;
      };
    };

    users.users.ucrm = {
      isSystemUser = true;
      group = "ucrm";
    };
    users.groups.ucrm = {};
  });
}
