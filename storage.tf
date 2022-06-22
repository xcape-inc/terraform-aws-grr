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

locals {
  grr_db_service_name = "${var.grr_project}_grr-db"
  database_fqdn = "${aws_service_discovery_service.database.name}.${aws_service_discovery_private_dns_namespace.grr.name}"
}

# TODO: lamba triggered by db healthy that does grr initialize; could be a general deployer to also copy the static ui stuff to s3

resource "aws_service_discovery_service" "database" {
  name = "database"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.grr.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }
}

resource "aws_ecs_service" "database" {
  name            = locals.grr_db_service_name
  cluster         = data.aws_ecs_cluster.ecs_cluster_for_services.arn
  task_definition = aws_ecs_task_definition.database.arn
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
    security_groups = [aws_security_group.database.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.database.arn
  }
}

resource "aws_security_group" "database" {
  description = "Security group to restrict access to containers that require access"
  name   = locals.grr_db_service_name
  vpc_id = var.service_vpc_id
}

resource "aws_ecs_task_definition" "database" {
  family = locals.grr_db_service_name
  cpu = 256
  memory = 1024
  network_mode = "awsvpc"
  container_definitions = jsonencode([
    {
      name      = "database"
      image     = "${var.database_image}:${var.database_image_tag}"
      cpu       = 256
      memory    = 1024
      essential = true
      command = ["--max-allowed-packet=1073741824"]
      environment = [
        {"name": "MYSQL_DATABASE", "value": var.grr_db_name},
        {"name": "MYSQL_USER", "value": var.grr_db_username},
        {"name": "MYSQL_ROOT_PASSWORD", "value": var.grr_db_root_password},
        {"name": "MYSQL_PASSWORD", "value": var.grr_db_password},
      ],
      portMappings = [
        {
          # hostPort = 0
          containerPort = var.grr_db_port
          protocol = "tcp"
        }
      ]
      healthCheck = {
        # This checks to ensure the created user has access to the database, meaning both exist and some permissions are set
        Command     = ["CMD", "/usr/bin/mysql", "--user=${var.grr_db_username}", "--password=${var.grr_db_password}", "--database=${var.grr_db_name}", "-qfsBe", "SELECT table_name FROM information_schema.TABLES LIMIT 1"]
        Interval    = 10
        Retries     = 10
        StartPeriod = 60
        Timeout     = 10
      }
      mountPoints = [
        {
          containerPath = "/var/lib/mysql"
          sourceVolume = "efs-db-data"
        }
      ]
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "ecs-cluster_${var.ecs_cluster_name}",
          "awslogs-create-group": "true",
          "awslogs-region": var.aws_region,
          "awslogs-stream-prefix": "containers/${locals.grr-db_service_name}"
        }
      }
    }
  ])

  volume {
    name = "efs-db-data"

    efs_volume_configuration {
      file_system_id          = aws_efs_file_system.database.id
      root_directory          = "/"
      transit_encryption      = "ENABLED"
      transit_encryption_port = 2999
      authorization_config {
        access_point_id = aws_efs_access_point.database.id
        iam             = "ENABLED"
      }
    }
  }

  # TODO: this needs some tuning
  task_role_arn = aws_iam_role.ecs_task_role_for_database.arn
  execution_role_arn = aws_iam_role.ecs_task_role_for_database.arn
}

resource "aws_efs_file_system" "database" {
  creation_token = locals.grr_db_service_name

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  performance_mode                = "generalPurpose"
  provisioned_throughput_in_mibps = "0"

  tags = {
    Name = locals.grr_db_service_name
  }

  throughput_mode = "bursting"
}

resource "aws_efs_access_point" "database" {
  file_system_id = aws_efs_file_system.database.id
}

resource "aws_efs_mount_target" "database" {
  file_system_id  = aws_efs_file_system.database.id
  security_groups = [aws_security_group.efs_database_to_mysql.id, var.vpc_egress_security_group_id]
  for_each = toset(var.service_subnet_ids)
  subnet_id = each.key
}

resource "aws_security_group" "efs_database_to_mysql" {
  description = "Security group for permitting access between the mysql database and its efs claim"
  name   = "${locals.grr_db_service_name}_efs_database_to_mysql"
  vpc_id = var.service_vpc_id
}

resource "aws_security_group_rule" "efs_database_to_mysql_egress" {
  cidr_blocks = ["0.0.0.0/0"]
  description = ""
  from_port = 0
  protocol = "-1"
  security_group_id = aws_security_group.efs_database_to_mysql.id
  to_port = 0
  type = "egress"
}

resource "aws_security_group_rule" "efs_database_to_mysql_ingress" {
  description = "Created by the LIW for EFS at 2021-04-02T12:32:14.918-07:00"
  from_port = 2049
  protocol = "tcp"
  security_group_id = aws_security_group.efs_database_to_mysql.id
  source_security_group_id = aws_security_group.database.id
  to_port = 2049
  type = "ingress"
}

resource "aws_security_group_rule" "efs_database_to_mysql_egress" {
  description = "Created by the LIW for EFS at 2021-04-02T12:32:14.915-07:00"
  from_port = 2049
  protocol = "tcp"
  security_group_id = aws_security_group.database.id
  source_security_group_id = aws_security_group.efs_database_to_mysql.id
  to_port = 2049
  type = "egress"
}

resource "aws_iam_role_policy_attachment" "ecsTaskRole_AmazonECSTaskExecutionRolePolicy_database" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.ecs_task_role_for_database.name
}

resource "aws_iam_role_policy_attachment" "ecsTaskRole_AmazonElasticFileSystemFullAccess_database" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonElasticFileSystemFullAccess"
  role       = aws_iam_role.ecs_task_role_for_database.name
}

resource "aws_iam_role" "ecs_task_role_for_database" {
  name               = "ecsTaskRole_for_${locals.grr_db_service_name}"

  assume_role_policy  = data.aws_iam_policy_document.ecs_task_execution_role_base.json
}

# resource "random_string" "grr_user_password" {
#   # Make the password extra spicy
#   length      = 32
#   special     = true
#   min_upper   = 8
#   min_lower   = 8
#   min_numeric = 8
#   min_special = 8
# }

resource "random_string" "grr_db_password" {
  # Make the password extra spicy
  length      = 32
  special     = true
  min_upper   = 8
  min_lower   = 8
  min_numeric = 8
  min_special = 8
}

resource "random_string" "grr_db_root_password" {
  # Make the password extra spicy
  length      = 32
  special     = true
  min_upper   = 8
  min_lower   = 8
  min_numeric = 8
  min_special = 8
}

# resource "random_string" "database_name_suffix" {
#   length  = 4
#   special = false
# }

# resource "google_sql_user" "grr_user" {
#   name     = "grr"
#   password = "${random_string.grr_user_password.result}"
#   instance = "${google_sql_database_instance.grr_db.name}"
# }

# resource "google_storage_bucket" "access_logs" {
#   name     = "${var.storage_access_logs_bucket_name}"
#   location = "${var.gcs_bucket_location}"
# }

# resource "google_storage_bucket" "client_installers" {
#   name          = "${var.client_installers_bucket_name}"
#   location      = "${var.gcs_bucket_location}"
#   force_destroy = true

#   logging {
#     log_bucket = "${google_storage_bucket.access_logs.name}"
#   }
# }

### client storage efs

resource "aws_efs_file_system" "clients" {
  creation_token = locals.grr_frontends_service_name

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  performance_mode                = "generalPurpose"
  provisioned_throughput_in_mibps = "0"

  tags = {
    Name = locals.grr_frontends_service_name
  }

  throughput_mode = "bursting"
}

resource "aws_efs_access_point" "clients" {
  file_system_id = aws_efs_file_system.clients.id
}

resource "aws_efs_mount_target" "clients" {
  file_system_id  = aws_efs_file_system.clients.id
  security_groups = [aws_security_group.efs_clients_to_apps.id, var.vpc_egress_security_group_id]
  for_each = toset(var.service_subnet_ids)
  subnet_id = each.key
}

resource "aws_security_group" "efs_clients_to_apps" {
  description = "Security group for permitting access between the various apps instances and the clients efs claim"
  name   = "${locals.grr_frontends_service_name}_efs_clients"
  vpc_id = var.service_vpc_id
}

resource "aws_security_group_rule" "efs_clients_to_apps_egress" {
  cidr_blocks = ["0.0.0.0/0"]
  description = ""
  from_port = 0
  protocol = "-1"
  security_group_id = aws_security_group.efs_clients_to_apps.id
  to_port = 0
  type = "egress"
}

resource "aws_security_group_rule" "efs_clients_to_apps_ingress" {
  description = "inbound to efs"
  from_port = 2049
  protocol = "tcp"
  security_group_id = aws_security_group.efs_clients_to_apps.id
  # This is the the rule for ec2 containers on ec2 type ecs
  # source_security_group_id = aws_security_group.frontends.id
  source_security_group_id = var.ecs_container_instance_security_group_id
  to_port = 2049
  type = "ingress"
}

resource "aws_security_group_rule" "efs_database_to_mysql_egress" {
  description = "Access from ecs instance to ${locals.grr_frontends_service_name}_efs_clients"
  from_port = 2049
  protocol = "tcp"
  # This is the the rule for ec2 containers on ec2 type ecs
  # security_group_id = aws_security_group.frontends.id
  security_group_id = var.ecs_container_instance_security_group_id
  source_security_group_id = aws_security_group.efs_database_to_mysql.id
  to_port = 2049
  type = "egress"
}
