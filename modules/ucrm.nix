{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.ucrm;
  ucrm = pkgs.callPackage ../pkgs/ucrm.nix { };
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
          default = "public";
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

  config = mkIf cfg.enable {

    systemd.services.ucrm-init = {
      description = "Ubiquiti CRM";
      wantedBy = [ "multi-user.target" ];
      after = [ "postgresql.service" ];

      environment = {
        POSTGRES_DB = cfg.postgres.db;
        POSTGRES_PORT = toString cfg.postgres.port;
        POSTGRES_USER = cfg.postgres.user;
        POSTGRES_HOST = cfg.postgres.host;
        RABBITMQ_HOST = cfg.rabbitmq.host;
        RABBITMQ_PORT = toString cfg.rabbitmq.port;
        SYMFONY_ENV = "prod";
        SYMFONY_DEBUG = toString 0;
        POSTGRES_SCHEMA = "ucrm";
        UNMS_POSTGRES_SCHEMA = "unms";
      };

      path = with pkgs; [ config.services.postgresql.package which jq ];

      preStart = ''
        export SECRET=ASDF
        export NODE_AUTH_KEY=ASDF
        export POSTGRES_PASSWORD=$(cat ${cfg.postgres.passwordFile})
        export PATH=${cfg.package}/scripts/bin:$PATH

        cat ${cfg.package}/app/config/parameters.yml.orig > /run/ucrm/parameters.yml
        ${pkgs.runtimeShell} -x ./scripts/parameters.sh
      '';

      script = ''
        export POSTGRES_PASSWORD=$(cat ${cfg.postgres.passwordFile})
        export PGPASSWORD="$POSTGRES_PASSWORD"
        export PATH=${cfg.package}/scripts/bin:$PATH
        set -x
        set -eu
        # from the makefile
        ${pkgs.runtimeShell} -x ./scripts/migrate.sh

        # from scripts/web.sh
        ./app/console crm:uas:bump -v
        ./app/console crm:version:bump --save-to-database -v
        ./app/console crm:unms:statistics:send --random-wait
        ./scripts/rabbitmq_ready.sh
        ./app/console rabbitmq:setup-fabric -v
        ./app/console crm:search:populate -v
        ./app/console crm:suspension:setupStaticSuspensionPage -v
        ./app/console crm:plugin:symlink -v
        ./app/console crm:plugin:ucrm-config -v
        ./app/console crm:plugin:update-database-information -v
        ./app/console crm:migration:reset-in-progress-states -v
        ./app/console crm:migration:update-price-minus-tax -v
        ./app/console crm:migration:setup -v
        ./app/console crm:unms:changes:sync -v
        ./app/console crm:unms:sync-site-relations -v
        ./app/console crm:unms:migrate-users -v
        ./app/console crm:unms:sync-users -v
        ./app/console crm:migration:set-sandbox -v
        ./app/console crm:unms:uimodel:sync -v
        ./app/console crm:service:status-update -v
        ./app/console crm:client:status-update -v
      '';

      serviceConfig = {
        User = "unms";
        WorkingDirectory = cfg.package;
        LogsDirectory = "ucrm";
        CacheDirectory = "ucrm";
        RuntimeDirectory = "ucrm";
        RuntimeDirectoryPreserve = true;
        StateDirectory = [ "ucrm/uploads" "ucrm/data/ticketing/attachments" ];
      };
    };

    systemd.services.ucrm-websockets = {
      sandbox = 2;

      apparmor = {
        enable = true;
        extraConfig = ''
          unix (create,getattr,getopt,setopt,shutdown),
          /run/ucrm/parameters.yml r,
          network tcp,
        '';
      };

      wantedBy = [ "multi-user.target" ];
      script = ''
        exec ${pkgs.nodejs}/bin/node ${cfg.package}/websockets/server.js
      '';

      serviceConfig = {
        User = "unms";
        MemoryDenyWriteExecute = false;
        PrivateNetwork = false;
      };
    };

    users.users.unms = {
      isSystemUser = true;
      group = "unms";
    };
    users.groups.unms = {};

    # networking.hosts = {
    #   "${cfg.postgres.host}" = [ "postgresql" ];
    # };
  };
}
