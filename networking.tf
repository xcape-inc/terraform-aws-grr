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

# resource "google_compute_network" "grr_network" {
#   name                    = "grr-network"
#   auto_create_subnetworks = false
#   description             = "Managed by Terraform. DO NOT EDIT. Network created exclusively for GRR and its components."
# }

# resource "google_compute_subnetwork" "grr_subnet" {
#   name                     = "grr-subnet"
#   ip_cidr_range            = "192.168.1.0/24"
#   region                   = "${var.aws_region}"
#   network                  = "${google_compute_network.grr_network.self_link}"
#   description              = "Managed by Terraform. DO NOT EDIT. Subnet used to house GRR instances for the specified region."
#   private_ip_google_access = true
# }

# resource "google_compute_global_address" "grr_frontend_lb" {
#   name        = "grr-frontend-lb"
#   description = "Managed by Terraform. DO NOT EDIT. Reserved IP address for GRR Frontend end load balancer."
# }

# resource "google_compute_global_address" "grr_adminui_lb" {
#   name        = "grr-adminui-lb"
#   description = "Managed by Terraform. DO NOT EDIT. Reserved IP address for GRR Admin UI."
# }

# resource "google_compute_firewall" "grr_default" {
#   name    = "grr-default"
#   network = "${google_compute_network.grr_network.self_link}"

#   allow {
#     protocol = "icmp"
#   }

#   allow {
#     protocol = "tcp"
#     ports    = ["22"]
#   }
# }

# resource "google_compute_firewall" "grr_allow_health_checks" {
#   name    = "grr-allow-health-checks"
#   network = "${google_compute_network.grr_network.self_link}"

#   allow {
#     protocol = "tcp"
#   }

#   source_ranges = [
#     "35.191.0.0/16",
#     "130.211.0.0/22",
#   ]

#   target_tags = ["allow-health-checks"]
# }

# resource "google_compute_firewall" "grr_frontend" {
#   name    = "grr-frontend"
#   network = "${google_compute_network.grr_network.self_link}"

#   allow {
#     protocol = "tcp"
#     ports    = ["${var.grr_frontend_port}", "${var.grr_frontend_monitoring_port}"]
#   }

#   target_tags = ["${var.grr_frontend_network_tag}"]
# }

resource "aws_security_group" "grr-alb" {
  name = "grr_for_${var.grr_project}"
  description = "controls access to the application load balancer"
  vpc_id = var.service_vpc_id

  ingress {
    from_port = 80
    protocol = "tcp"
    to_port = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = var.grr_frontend_port
    protocol = "tcp"
    to_port = var.grr_frontend_port
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    protocol = "-1"
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "grr" {
  name = "grr_for_${var.grr_project}"
  subnets = var.service_subnet_ids
  security_groups = [aws_security_group.grr-alb.id]
}

resource "aws_lb_listener" "grr-http"   {
  load_balancer_arn = aws_lb.grr.arn
  port = 80
  protocol = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      status_code = "HTTP_301"
      protocol = "HTTPS"
      port = var.grr_frontend_port
    }
  }
}

resource "aws_lb_listener" "grr-https" {
  load_balancer_arn = aws_lb.grr.arn
  port = var.grr_frontend_port
  protocol = "HTTPS"
  certificate_arn = aws_acm_certificate_validation.grr.certificate_arn
  ssl_policy = "ELBSecurityPolicy-2016-08"

  default_action {
    type = "authenticate-oidc"

    authenticate_oidc {
      authorization_endpoint = var.grr_adminui_idp_authorization_endpoint
      client_id              = var.grr_adminui_idp_client_id
      client_secret          = var.grr_adminui_idp_client_secret
      issuer                 = var.grr_adminui_idp_issuer
      token_endpoint         = var.grr_adminui_idp_token_endpoint
      user_info_endpoint     = var.grr_adminui_idp_user_info_endpoint
    }
  }

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.grr-adminUi.arn
  }
}

# TODO: better health checks
# TODO: need to add the lb rules for routing
resource "aws_lb_target_group" "grr-adminUi" {
  depends_on = [aws_lb.demo-alb]
  name = "grr_for_${var.grr_project}_adminUi"
  port = 80
  protocol = "HTTP"
  vpc_id = var.service_vpc_id
  target_type = "instance"
  health_check {
    path = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 60
    interval            = 300
  }
  lifecycle {
    create_before_destroy = true
  }
  stickiness {
    type = "lb_cookie"
    cookie_duration = 86400
  }
  deregistration_delay = 60
}

resource "aws_security_group_rule" "grr-alb_to_frontend" {
  description = "Inbound to ephemeral ports from load balancer"
  from_port = 32768
  protocol = "tcp"
  to_port = 65535
  security_group_id = var.grr_frontend_network_security_group_id
  source_security_group_id = aws_security_group.grr-alb.id
  type = "ingress"
}
