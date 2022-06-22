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

## TODO: add some infra to host a s3 bucket with the statics as a cdn
## hooked to the alb instead of using the wsgi for it

resource "random_string" "grr_adminui_password" {
  # Make the password extra hot
  length      = 32
  special     = true
  min_upper   = 8
  min_lower   = 8
  min_numeric = 8
  min_special = 8
}

module "grr_adminui_container" {
  # Pin module for build determinism
  source = "github.com/terraform-google-modules/terraform-google-container-vm?ref=f299e4c3b13a987482f830489222006ef85075ed"

  container = {
    image = "${var.grr_adminui_image}:${var.grr_adminui_image_tag}"

    env = [
      {
        name  = "EXTERNAL_HOSTNAME"
        value = "${var.grr_adminui_external_hostname}"
      },
      {
        name  = "NO_CLIENT_UPLOAD"
        value = "false"
      },
      {
        name  = "ADMINUI_PORT"
        value = "${var.grr_adminui_port}"
      },
      {
        name  = "ADMINUI_WEBAUTH_MANAGER"
        value = "IAPWebAuthManager"
      },
      {
        name  = "FRONTEND_BIND_ADDRESS"
        value = "${var.grr_frontend_address}"
      },
      {
        name  = "FRONTEND_BIND_PORT"
        value = "${var.grr_frontend_port}"
      },
      {
        name  = "FRONTEND_CERTIFICATE"
        value = "${tls_locally_signed_cert.frontend.cert_pem}"
      },
      {
        name  = "MONITORING_HTTP_PORT"
        value = "${var.grr_adminui_monitoring_port}"
      },
      {
        name  = "MYSQL_HOST"
        value = "${google_sql_database_instance.grr_db.ip_address.0.ip_address}"
      },
      {
        name  = "MYSQL_PORT"
        value = 3306
      },
      {
        name  = "MYSQL_DATABASE_NAME"
        value = "${google_sql_database.grr_db.name}"
      },
      {
        name  = "MYSQL_DATABASE_USERNAME"
        value = "${google_sql_user.grr_user.name}"
      },
      {
        name  = "MYSQL_DATABASE_PASSWORD"
        value = "${random_string.grr_user_password.result}"
      },
      {
        name  = "ADMIN_USER"
        value = "${var.grr_adminui_username}"
      },
      {
        name  = "ADMIN_PASSWORD"
        value = ${var.grr_adminui_password}
      },
      {
        name  = "FRONTEND_PUBLIC_SIGNING_KEY"
        value = "${base64encode(data.tls_public_key.frontend_executable_signing.public_key_pem)}"
      },
      {
        name  = "CLOUD_PROJECT_ID"
        value = "${data.google_project.project.number}"
      },
      {
        name  = "CLOUD_PROJECT_NAME"
        value = "${var.gce_project}"
      },
      {
        name  = "CLOUD_BACKEND_SERVICE_NAME"
        value = "${var._admin_ui_backend_service_name}"
      },
    ]
  }

  restart_policy = "Always"
}

resource "random_id" "adminui_instance_config" {
  keepers = {
    # Automatically generate a new id if OS image or container config changes
    container_os_image   = "${module.grr_adminui_container.vm_container_label}"
    container_definition = "${module.grr_adminui_container.metadata_value}"
  }

  byte_length = 2
}

resource "google_compute_instance_template" "grr_adminui" {
  name        = "grr-adminui-${random_id.adminui_instance_config.hex}"
  description = "Managed by Terraform. DO NOT EDIT. Describes how to provision an independent GRR Admin UI."

  tags = [
    "${var.grr_adminui_network_tag}",
    "allow-health-checks",
  ]

  labels {
    "container-vm" = "${module.grr_adminui_container.vm_container_label}"
  }

  metadata {
    "gce-container-declaration" = "${module.grr_adminui_container.metadata_value}"
    "google-logging-enabled"    = "true"

    # Case sensitive
    "enable-oslogin" = "TRUE"
  }

  machine_type = "${var.grr_adminui_machine_type}"

  disk {
    boot         = true
    source_image = "${module.grr_adminui_container.source_image}"
  }

  network_interface {
    subnetwork = "${google_compute_subnetwork.grr_subnet.self_link}"

    # Set up NAT
    access_config {}
  }

  lifecycle {
    create_before_destroy = true
  }

  service_account {
    # TODO specify a locked down service account
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}

resource "google_compute_instance_group_manager" "grr_adminuis" {
  name        = "grr-adminuis"
  description = "Managed by Terraform. DO NOT EDIT. Group manager for GRR AdminUIs."

  base_instance_name = "grr-adminuis"

  instance_template = "${google_compute_instance_template.grr_adminui.self_link}"

  update_strategy = "ROLLING_UPDATE"

  rolling_update_policy {
    type              = "PROACTIVE"
    minimal_action    = "RESTART"
    max_surge_percent = 100
    min_ready_sec     = 20
  }

  target_size = "${var.grr_adminui_target_size}"

  # TODO Make region automatic
  zone = "${var.aws_region}-b"

  named_port {
    name = "service"
    port = "${var.grr_adminui_port}"
  }

  named_port {
    name = "monitoring"
    port = "${var.grr_adminui_monitoring_port}"
  }

  auto_healing_policies {
    health_check      = "${google_compute_health_check.grr_adminui_autohealing.self_link}"
    initial_delay_sec = 60
  }
}

resource "google_compute_health_check" "grr_adminui_autohealing" {
  name = "grr-adminui-autohealing"

  timeout_sec        = 10
  check_interval_sec = 10

  tcp_health_check {
    port = "${var.grr_adminui_port}"
  }
}

resource "google_compute_health_check" "grr_adminui_loadbalancing" {
  name = "grr-adminui-loadbalancing"

  timeout_sec        = 10
  check_interval_sec = 10

  tcp_health_check {
    port = "${var.grr_adminui_port}"
  }
}

resource "google_compute_health_check" "grr_adminui_loadbalancing_monitoring" {
  name = "grr-adminui-monitoring"

  timeout_sec        = 10
  check_interval_sec = 10

  tcp_health_check {
    port = "${var.grr_adminui_monitoring_port}"
  }
}

# resource "google_compute_ssl_certificate" "grr_adminui" {
#   name        = "grr-adminui-certificate-${random_string.certificate_name_suffix.result}"
#   private_key = "${var.grr_adminui_ssl_cert_private_key}"
#   certificate = "${file("${var.grr_adminui_ssl_cert_path}")}"

#   lifecycle {
#     create_before_destroy = true
#   }
# }

# resource "random_string" "certificate_name_suffix" {
#   length  = 4
#   special = false
# }

# TODO: convert these to alb rules
resource "google_compute_url_map" "grr_adminui" {
  name        = "grr-adminui"
  description = "Managed by Terraform. DO NOT EDIT. GRR AdminUI url map"

  default_service = "${google_compute_backend_service.grr_adminui.self_link}"

  host_rule {
    hosts        = ["${var.grr_adminui_external_hostname}"]
    path_matcher = "allpaths"
  }

  path_matcher {
    name            = "allpaths"
    default_service = "${google_compute_backend_service.grr_adminui.self_link}"

    path_rule {
      paths   = ["/*"]
      service = "${google_compute_backend_service.grr_adminui.self_link}"
    }

    # Note: This is hosting the internal stats server thingy; not sure we need this
    path_rule {
      paths   = ["/varz"]
      service = "${google_compute_backend_service.grr_adminui_monitoring.self_link}"
    }

    # TODO: should this be /statics?
    path_rule {
      paths   = ["/${var.client_installers_bucket_root}/*"]
      service = "${google_compute_backend_bucket.client_installers.self_link}"
    }
  }
}

# This is the alb
resource "google_compute_target_https_proxy" "grr_adminui" {
  name             = "grr-adminui"
  url_map          = "${google_compute_url_map.grr_adminui.self_link}"
  ssl_certificates = ["${google_compute_ssl_certificate.grr_adminui.self_link}"]
}

resource "google_compute_global_forwarding_rule" "grr_adminui" {
  name       = "grr-adminui"
  target     = "${google_compute_target_https_proxy.grr_adminui.self_link}"
  port_range = "${var.grr_adminui_port}"
  ip_address = "${google_compute_global_address.grr_adminui_lb.address}"
}

# lb target group
resource "google_compute_backend_service" "grr_adminui" {
  name          = "${var._admin_ui_backend_service_name}"
  description   = "Managed by Terraform. DO NOT EDIT. GRR adminui backend service for responding to clients"
  port_name     = "service"
  protocol      = "HTTP"
  health_checks = ["${google_compute_health_check.grr_adminui_loadbalancing.self_link}"]

  backend {
    group = "${google_compute_instance_group_manager.grr_adminuis.instance_group}"
  }

  iap {
    oauth2_client_id     = "${var.grr_adminui_iap_client_id}"
    oauth2_client_secret = "${var.grr_adminui_iap_client_secret}"
  }
}

# lb target group
resource "google_compute_backend_service" "grr_adminui_monitoring" {
  name          = "grr-adminui-monitoring"
  description   = "Managed by Terraform. DO NOT EDIT. GRR adminui backend service for monitoring"
  port_name     = "monitoring"
  protocol      = "HTTP"
  health_checks = ["${google_compute_health_check.grr_adminui_loadbalancing_monitoring.self_link}"]

  backend {
    group = "${google_compute_instance_group_manager.grr_adminuis.instance_group}"
  }
}

resource "google_compute_backend_bucket" "client_installers" {
  name        = "client-installers"
  bucket_name = "${google_storage_bucket.client_installers.name}"
  description = "Managed by Terraform. DO NOT EDIT. Serves client installers behind https load balancer"
}
