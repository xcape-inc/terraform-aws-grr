#  Copyright 2018-2019 Spotify AB.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing,
#  software distributed under the License is distributed on an
#  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
#  KIND, either express or implied.  See the License for the
#  specific language governing permissions and limitations
#  under the License.

#  Copyright 2018-2019 Spotify AB.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing,
#  software distributed under the License is distributed on an
#  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
#  KIND, either express or implied.  See the License for the
#  specific language governing permissions and limitations
#  under the License.

####

locals {
  grr_frontends_service_name = "${var.grr_project}_grr-frontends"
}

resource "aws_ecs_service" "frontend_containers" {
  name            = locals.grr_frontends_service_name
  cluster         = data.aws_ecs_cluster.ecs_cluster_for_services.arn
  task_definition = aws_ecs_task_definition.frontends.arn
  desired_count   = 1
  # launch_type     = "EC2"

  # load_balancer {
  #   target_group_arn = aws_lb_target_group.grr-adminUi.arn
  #   container_name = jsondecode(aws_ecs_task_definition.database.container_definitions)[0].name
  #   container_port = jsondecode(aws_ecs_task_definition.database.container_definitions)[0].portMappings[0].containerPort
  # }
  health_check_grace_period_seconds = 60

  capacity_provider_strategy {
    base              = 0
    weight            = 1
    capacity_provider = var.ecs_capacity_provider_name
  }

  network_configuration {
    subnets = var.service_subnet_ids
    security_groups = [aws_security_group.frontends.id]
    assign_public_ip = false
  }
}

# Note: in ec2 bridge network mode, this wont be used.  But we will create it anyways
resource "aws_security_group" "frontends" {
  description = "Security group to restrict access to containers that require access"
  name   = locals.grr_frontends_service_name
  vpc_id = var.service_vpc_id
}

resource "aws_security_group_rule" "database_ingress_frontends" {
  description = "Allow frontends to access the database"
  from_port = var.grr_db_port
  protocol = "tcp"
  to_port = var.grr_db_port
  security_group_id = aws_security_group.database.id
  source_security_group_id = aws_security_group.frontends.id
  type = "ingress"
}

# TODO: need all the stuff for task auto scaling to meet the input variable for frontends count
resource "aws_ecs_task_definition" "frontends" {
  family = locals.grr_frontends_service_name
  cpu = 256
  memory = 1024
  # We want the default for the cluster type, either awsvpc for fargate or bridge mode for ec2
  # network_mode = "awsvpc"
  container_definitions = jsonencode([
    {
      name      = "frontends"
      image     = "${var.grr_frontend_image}:${var.grr_frontend_image_tag}"
      cpu       = 256
      memory    = 1024
      essential = true
      entryPoint = ["/bin/bash"]
      command = [
        "-ce", <<FOO
(if [ ! -e /etc/grr/server.local.yaml ]; then mkdir -p ${locals.CERTS_PATH}; (echo '---
---
# Frontend
Frontend.bind_port: "$${FRONTEND_SERVER_PORT}"

# Key Management
Server.rsa_key_length: "'"$${SERVER_RSA_KEY_LENGTH}"'"
PrivateKeys.server_key: "%('"$${FRONTEND_PRIVATE_KEY_PATH}"'|file)"
Frontend.certificate: "%('"$${FRONTEND_CERT_PATH}"'|file)"
PrivateKeys.executable_signing_private_key: "%('"$${FRONTEND_PRIVATE_SIGNING_KEY_PATH}"'|file)"
PrivateKeys.ca_key: "%('"$${CA_PRIVATE_KEY_PATH}"'|file)"
CA.certificate: "%('"$${CA_CERT_PATH}"'|file)"

# Database
Database.implementation: MysqlDB
Mysql.host: "'"$${MYSQL_HOST}"'"
Mysql.port: "'"$${MYSQL_PORT}"'"
Mysql.database: "'"$${MYSQL_DATABASE_NAME}"'"
Mysql.username: "'"$${MYSQL_DATABASE_USERNAME}"'"
Mysql.password: "'"$${MYSQL_DATABASE_PASSWORD}"'"

# We initialize via config file and not grr_config_updater
Server.initialized: True

# Health Checking
Monitoring.http_port: "'"$${MONITORING_HTTP_PORT}"'"

# Logging
Logging.engines: "stderr"
Logging.verbose: True

# Client Packing
Client.name: grr
Client.server_urls: "http://%(CLIENT_PACKING_FRONTEND_HOST|env):%(FRONTEND_SERVER_PORT|env)/"
Client.executable_signing_public_key: "%(%(FRONTEND_PUBLIC_SIGNING_KEY_PATH|env)|file)"
ClientRepacker.output_basename: "%(Client.prefix)%(Client.name)_%(Source.version_string)_%(Client.arch)_%(CLIENT_INSTALLER_FINGERPRINT|env)"

Target:Darwin:
  Config.includes:
    - "/etc/%(Client.name).labels.yaml"

Target:Linux:
  Config.includes:
    - "/etc/%(Client.name).labels.yaml"

Target:Windows:
  Config.includes:
    - "%(Client.install_path)/%(Client.binary_name).labels.yaml"
' > /etc/grr/server.local.yaml; fi); \
(if [ ! -e $FRONTEND_CERT_PATH ]; then (echo "$FRONTEND_CERT" | base64 -d > $FRONTEND_CERT_PATH); fi); \
(if [ ! -e $FRONTEND_PRIVATE_KEY_PATH ]; then (echo "$FRONTEND_PRIVATE_KEY" | base64 -d > $FRONTEND_PRIVATE_KEY_PATH); fi); \
(if [ ! -e $FRONTEND_PRIVATE_SIGNING_KEY_PATH ]; then (echo "$FRONTEND_PRIVATE_SIGNING_KEY" | base64 -d > $FRONTEND_PRIVATE_SIGNING_KEY_PATH); fi); \
(if [ ! -e $FRONTEND_PUBLIC_SIGNING_KEY_PATH ]; then (echo "$FRONTEND_PUBLIC_SIGNING_KEY" | base64 -d > $FRONTEND_PUBLIC_SIGNING_KEY_PATH); fi); \
(if [ ! -e $CA_CERT_PATH ]; then (echo "$CA_CERT" | base64 -d > $CA_CERT_PATH); fi); \
(if [ ! -e $CA_PRIVATE_KEY_PATH ]; then (echo "$CA_PRIVATE_KEY" | base64 -d > $CA_PRIVATE_KEY_PATH); fi); \
unset CA_CERT_PATH; unset CA_CERT; unset CA_PRIVATE_KEY_PATH; unset CA_PRIVATE_KEY; \
unset MONITORING_HTTP_PORT; \
unset MYSQL_HOST; unset MYSQL_PORT; unset MYSQL_DATABASE_NAME; unset MYSQL_DATABASE_USERNAME; unset MYSQL_DATABASE_PASSWORD; \
unset FRONTEND_CERT_PATH; unset FRONTEND_PRIVATE_KEY_PATH; unset FRONTEND_PRIVATE_SIGNING_KEY_PATH; FRONTEND_PUBLIC_SIGNING_KEY_PATH; \

          name  = "FRONTEND_SERVER_PORT"
          name  = "CLIENT_PACKING_FRONTEND_HOST"
          name  = "CLIENT_INSTALLER_FINGERPRINT"
          name  = "FRONTEND_PUBLIC_SIGNING_KEY"
          name  = "CLIENT_INSTALLER_BUCKET"
          name  = "CLIENT_INSTALLER_ROOT"
          name  = "SERVER_RSA_KEY_LENGTH"
          name  = "FRONTEND_CERT"
          name  = "FRONTEND_PRIVATE_KEY"
          name  = "FRONTEND_PRIVATE_SIGNING_KEY"

exec $GRR_VENV/bin/grr_server \
  --component frontend \
  --secondary_configs /etc/grr/server.local.yaml
FOO
# TODO: finish unset stuff
      ]
      environment = [
        {
          name = "FRONTEND_CERT_PATH"
          value = "${locals.CERTS_PATH}/frontend-cert.pem"
        },
        {
          name = "FRONTEND_PRIVATE_KEY_PATH"
          value = "${locals.CERTS_PATH}/frontend-private.key"
        },
        {
          name = "FRONTEND_PRIVATE_SIGNING_KEY_PATH"
          value = "${locals.CERTS_PATH}/frontend-signing.key"
        },
        {
          name = "FRONTEND_PUBLIC_SIGNING_KEY_PATH"
          value = "${locals.CERTS_PATH}/frontend-signing.pub"
        },
        {
          name = "CA_CERT_PATH"
          value = "${locals.CERTS_PATH}/ca-cert.pem"
        },
        # TODO: not sure this is needed
        {
          name = "CA_PRIVATE_KEY_PATH"
          value = "${locals.CERTS_PATH}/ca-private.key"
        },
        {
          name  = "FRONTEND_SERVER_PORT"
          value = "${var.grr_frontend_port}"
        },
        {
          name  = "MONITORING_HTTP_PORT"
          value = "${var.grr_frontend_monitoring_port}"
        },
        {
          name  = "CLIENT_PACKING_FRONTEND_HOST"
          value = locals.fqdn
        },
        {
          name  = "CLIENT_INSTALLER_FINGERPRINT"
          value = "${random_id.client_installer_fingerprint.dec}"
        },
        {
          name  = "FRONTEND_PUBLIC_SIGNING_KEY"
          value = "${base64encode(data.tls_public_key.frontend_executable_signing.public_key_pem)}"
        },
        {
          name  = "CLIENT_INSTALLER_BUCKET"
          value = "${google_storage_bucket.client_installers.name}"
        },
        {
          name  = "CLIENT_INSTALLER_ROOT"
          value = "${var.client_installers_bucket_root}"
        },
        {
          name  = "SERVER_RSA_KEY_LENGTH"
          value = "${var.frontend_rsa_key_length}"
        },
        {
          name  = "FRONTEND_CERT"
          value = "${base64encode(tls_locally_signed_cert.frontend.cert_pem)}"
        },
        {
          name  = "FRONTEND_PRIVATE_KEY"
          value = "${base64encode(tls_private_key.frontend.private_key_pem)}"
        },
        {
          name  = "FRONTEND_PRIVATE_SIGNING_KEY"
          value = "${base64encode(tls_private_key.frontend_executable_signing.private_key_pem)}"
        },
        {
          name  = "MYSQL_HOST"
          value = locals.database_fqdn
        },
        {
          name  = "MYSQL_PORT"
          value = "${var.grr_db_port}"
        },
        {
          name  = "MYSQL_DATABASE_NAME"
          value = var.grr_db_name
        },
        {
          name  = "MYSQL_DATABASE_USERNAME"
          value = var.grr_db_username
        },
        {
          name  = "MYSQL_DATABASE_PASSWORD"
          value = var.grr_db_password
        },
        {
          name  = "CA_CERT"
          value = base64encode(tls_self_signed_cert.frontend_ca.cert_pem)
        },
        # Note: Not sure this is needed for front end
        {
          name  = "CA_PRIVATE_KEY"
          value = base64encode(tls_private_key.frontend_ca.private_key_pem)
        },
      ]
      healthcheck = {
        # TODO: update this to hit a functioning auth-free 200 endpoint, maybe w curl?
        Command     = ["CMD", "wget", "http://127.0.0.1/${var.grr_worker_monitoring_port}"]
        Interval    = 10
        Retries     = 10
        StartPeriod = 60
        Timeout     = 10
      }
      portMappings = [
        {
          # hostPort = 0
          containerPort = var.grr_frontend_port
          protocol = "tcp"
        }
      ]
      # TODO: find out if there are places we would need to "mount" to make read only file system viable
      mountPoints = [
        {
          # TODO: mount the location for clients and maybe fix the path in config
          containerPath = "/tbd"
          sourceVolume = "efs-clients-data"
        }
      ]
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "ecs-cluster_${var.ecs_cluster_name}",
          "awslogs-create-group": "true",
          "awslogs-region": var.aws_region,
          "awslogs-stream-prefix": "containers/${locals.grr_frontends_service_name}"
        }
      }
    }
  ])

  volume {
    name = "efs-clients-data"

    efs_volume_configuration {
      file_system_id          = aws_efs_file_system.clients.id
      root_directory          = "/"
      transit_encryption      = "ENABLED"
      transit_encryption_port = 2999
      authorization_config {
        access_point_id = aws_efs_access_point.clients.id
        iam             = "ENABLED"
      }
    }
  }

  # TODO: this needs some tuning
  task_role_arn = aws_iam_role.ecs_task_role_for_frontends.arn
  execution_role_arn = aws_iam_role.ecs_task_role_for_frontends.arn
}

resource "aws_iam_role_policy_attachment" "ecsTaskRole_AmazonECSTaskExecutionRolePolicy_frontends" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.ecs_task_role_for_frontends.name
}

resource "aws_iam_role_policy_attachment" "ecsTaskRole_AmazonElasticFileSystemFullAccess_frontends" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonElasticFileSystemFullAccess"
  role       = aws_iam_role.ecs_task_role_for_frontends.name
}

resource "aws_iam_role" "ecs_task_role_for_frontends" {
  name               = "ecsTaskRole_for_${locals.grr_frontends_service_name}"

  assume_role_policy  = data.aws_iam_policy_document.ecs_task_execution_role_base.json
}

# module "grr_frontend_container" {
#   # Pin module for build determinism
#   source = "github.com/terraform-google-modules/terraform-google-container-vm?ref=f299e4c3b13a987482f830489222006ef85075ed"

#   container = {
#     image = "${var.grr_frontend_image}:${var.grr_frontend_image_tag}"

#     env = [
#       {
#         name  = "NO_CLIENT_UPLOAD"
#         value = "false"
#       },
#       {
#         name  = "FRONTEND_SERVER_PORT"
#         value = "${var.grr_frontend_port}"
#       },
#       {
#         name  = "MONITORING_HTTP_PORT"
#         value = "${var.grr_frontend_monitoring_port}"
#       },
#       {
#         name  = "MYSQL_HOST"
#         value = "${google_sql_database_instance.grr_db.ip_address.0.ip_address}"
#       },
#       {
#         name  = "MYSQL_PORT"
#         value = var.grr_db_port
#       },
#       {
#         name  = "MYSQL_DATABASE_NAME"
#         value = "${google_sql_database.grr_db.name}"
#       },
#       {
#         name  = "MYSQL_DATABASE_USERNAME"
#         value = "${google_sql_user.grr_user.name}"
#       },
#       {
#         name  = "MYSQL_DATABASE_PASSWORD"
#         value = "${random_string.grr_user_password.result}"
#       },
#       {
#         name  = "CLIENT_PACKING_FRONTEND_HOST"
#         value = "${var.grr_frontend_address}"
#       },
#       {
#         name  = "CLIENT_INSTALLER_FINGERPRINT"
#         value = "${random_id.client_installer_fingerprint.dec}"
#       },
#       {
#         name  = "FRONTEND_PUBLIC_SIGNING_KEY"
#         value = "${base64encode(data.tls_public_key.frontend_executable_signing.public_key_pem)}"
#       },
#       {
#         name  = "CLIENT_INSTALLER_BUCKET"
#         value = "${google_storage_bucket.client_installers.name}"
#       },
#       {
#         name  = "CLIENT_INSTALLER_ROOT"
#         value = "${var.client_installers_bucket_root}"
#       },
#       {
#         name  = "SERVER_RSA_KEY_LENGTH"
#         value = "${var.frontend_rsa_key_length}"
#       },
#       {
#         name  = "FRONTEND_CERT"
#         value = "${base64encode(tls_locally_signed_cert.frontend.cert_pem)}"
#       },
#       {
#         name  = "CA_CERT"
#         value = "${base64encode(tls_self_signed_cert.frontend_ca.cert_pem)}"
#       },
#       {
#         name  = "FRONTEND_PRIVATE_KEY"
#         value = "${base64encode(tls_private_key.frontend.private_key_pem)}"
#       },
#       {
#         name  = "CA_PRIVATE_KEY"
#         value = "${base64encode(tls_private_key.frontend_ca.private_key_pem)}"
#       },
#       {
#         name  = "FRONTEND_PRIVATE_SIGNING_KEY"
#         value = "${base64encode(tls_private_key.frontend_executable_signing.private_key_pem)}"
#       },
#     ]
#   }

#   restart_policy = "Always"
# }

resource "random_id" "client_installer_fingerprint" {
  keepers = {
    # Generate a new fingeprint everytime the CA or frontend image changes
    ca_cert            = "${tls_self_signed_cert.frontend_ca.cert_pem}"
    frontend_image     = "${var.grr_frontend_image}"
    frontend_image_tag = "${var.grr_frontend_image_tag}"
  }

  byte_length = 2
}

resource "random_id" "frontend_instance_config" {
  keepers = {
    # Automatically generate a new id if OS image or container config changes
    container_os_image   = "${module.grr_frontend_container.vm_container_label}"
    container_definition = "${module.grr_frontend_container.metadata_value}"
  }

  byte_length = 2
}
