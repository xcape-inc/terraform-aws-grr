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
  grr_worker_service_name = "${var.grr_project}_grr-workers"
  CERTS_PATH = "/etc/grr/certs"
}

resource "aws_ecs_service" "worker_container" {
  name            = locals.grr_worker_service_name
  cluster         = data.aws_ecs_cluster.ecs_cluster_for_services.arn
  task_definition = aws_ecs_task_definition.workers.arn
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
    security_groups = [aws_security_group.workers.id]
    assign_public_ip = false
  }
}

resource "aws_security_group" "workers" {
  description = "Security group to restrict access to containers that require access"
  name   = locals.grr_worker_service_name
  vpc_id = var.service_vpc_id
}

resource "aws_security_group_rule" "database_ingress_workers" {
  description = "Allow workers to access the database"
  from_port = var.grr_db_port
  protocol = "tcp"
  to_port = var.grr_db_port
  security_group_id = aws_security_group.database.id
  source_security_group_id = aws_security_group.workers.id
  type = "ingress"
}

# TODO: need all the stuff for task auto scaling to meet the input variable for workers count
resource "aws_ecs_task_definition" "workers" {
  family = locals.grr_worker_service_name
  cpu = 256
  memory = 1024
  network_mode = "awsvpc"
  container_definitions = jsonencode([
    {
      name      = "workers"
      image     = "${var.grr_worker_image}:${var.grr_worker_image_tag}"
      cpu       = 256
      memory    = 1024
      essential = true
      entryPoint = ["/bin/bash"]
      command = [
        "-ce", <<FOO
(if [ ! -e /etc/grr/server.local.yaml ]; then mkdir -p ${locals.CERTS_PATH}; (echo '---
# Worker
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
' > /etc/grr/server.local.yaml); fi); \
(if [ ! -e $CA_CERT_PATH ]; then (echo "$CA_CERT" | base64 -d > $CA_CERT_PATH); fi); \
(if [ ! -e $CA_PRIVATE_KEY_PATH ]; then (echo "$CA_PRIVATE_KEY" | base64 -d > $CA_PRIVATE_KEY_PATH); fi); \
unset CA_CERT_PATH; unset CA_CERT; unset CA_PRIVATE_KEY_PATH; unset CA_PRIVATE_KEY; \
unset MONITORING_HTTP_PORT; \
unset MYSQL_HOST; unset MYSQL_PORT; unset MYSQL_DATABASE_NAME; unset MYSQL_DATABASE_USERNAME; unset MYSQL_DATABASE_PASSWORD; \
exec $GRR_VENV/bin/grr_server \
  --component worker \
  --secondary_configs /etc/grr/server.local.yaml
FOO
      ]
      environment = [
        {
          name = "CA_CERT_PATH"
          value = "${locals.CERTS_PATH}/ca-cert.pem"
        },
        {
          name = "CA_PRIVATE_KEY_PATH"
          value = "${locals.CERTS_PATH}/ca-private.key"
        },
        {
          name  = "MONITORING_HTTP_PORT"
          value = "${var.grr_worker_monitoring_port}"
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
        # The private key of the CA is needed by workers as they are responsible for issuing new client certs
        {
          name  = "CA_PRIVATE_KEY"
          value = base64encode(tls_private_key.frontend_ca.private_key_pem)
        },
      ]
      healthCheck = {
        # TODO: update this to have the full path of the binary and maybe use curl instead?
        Command     = ["CMD", "wget", "http://127.0.0.1/${var.grr_worker_monitoring_port}"]
        Interval    = 10
        Retries     = 10
        StartPeriod = 60
        Timeout     = 10
      }
      portMappings = [
        {
          # hostPort = 0
          containerPort = var.grr_worker_monitoring_port
          protocol = "tcp"
        }
      ]
      # TODO: find out if there are places we would need to "mount" to make read only file system viable (like tmp)
      # mountPoints = [
      #   {
      #     containerPath = "/var/lib/mysql"
      #     sourceVolume = "efs-db-data"
      #   }
      # ]
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "ecs-cluster_${var.ecs_cluster_name}",
          "awslogs-create-group": "true",
          "awslogs-region": var.aws_region,
          "awslogs-stream-prefix": "containers/${locals.grr_worker_service_name}"
        }
      }
    }
  ])

  # TODO: this needs some tuning
  task_role_arn = aws_iam_role.ecs_task_role_for_workers.arn
  execution_role_arn = aws_iam_role.ecs_task_role_for_workers.arn
}

resource "aws_iam_role_policy_attachment" "ecsTaskRole_AmazonECSTaskExecutionRolePolicy_workers" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.ecs_task_role_for_workers.name
}

resource "aws_iam_role" "ecs_task_role_for_workers" {
  name               = "ecsTaskRole_for_${locals.grr_db_service_name}"

  assume_role_policy  = data.aws_iam_policy_document.ecs_task_execution_role_base.json
}
