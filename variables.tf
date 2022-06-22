locals {
  default_grr_image = "grrdocker/grr"
  default_grr_image_tag = "v3.4.6.0"
}

# TODO: would this be an efs claim?  I think so but...
# variable "client_installers_bucket_root" {
#   description = "The root directory where grr client installers should be uploaded to in the client installer bucket"
#   default     = "installers"
#   type = string
# }

variable "aws_region" {
  description = "Region to deploy AWS assets to"
  type = string
}

# note: this will be repurposed as the parent sub domain
variable "grr_project" {
  description = "Project name to deploy assests for"
  type = string
}

variable "grr_frontend_port" {
  description = "GRR frontend port that clients will connect to"
  default     = 443
  type = number
}

# Note: we may or may not use this.
variable "grr_frontend_monitoring_port" {
  description = "GRR frontend monitoring stats port"
  default     = 5222
  type = number
}

variable "grr_frontend_network_security_group_id" {
  description = "The id of the security group (which acts as a firewall) to use to open ports for GRR frontend"
  type = string
}

variable "grr_frontend_sub_domain" {
  type        = string
  description = "The sub domain to use for the GRR frontend address. If the full address of the server is to be \"grr.mydomain.com\", the value of this would be \"grr\""
  default     = "grr.${var.grr_project}"
}

variable "grr_adminui_image" {
  description = "Docker image to run for GRR adminui"
  type = string
  default = locals.default_grr_image
}

variable "grr_adminui_image_tag" {
  description = "Docker image tag to pull of image specified by grr_adminui_image"
  type = string
  default = locals.default_grr_image_tag
}

# variable "grr_adminui_port" {
#   description = "GRR AdminUI port that clients will connect to"
#   default     = 443
#   type = number
# }

variable "grr_adminui_monitoring_port" {
  description = "GRR AdminUI monitoring stats port"
  default     = 5222
  type = number
}

# variable "grr_adminui_network_security_group_id" {
#   description = "The id of the security group (which acts as a firewall) to us to open ports for GRR admin UI"
#   type = string
# }

variable "grr_adminui_target_size" {
  description = "The number of GRR AdminUI instances that should always be running"
  default     = 2
  type = number
}

# TODO: this needs a little fix to work with ANY OIDC compliant provider
variable "grr_adminui_idp_client_id" {
  description = "The OAuth2 Client id for the previously set up IdP Credential"
  type = string
}

variable "grr_adminui_idp_client_secret" {
  # We rely on the redirect_uri being hard to compromise and accept the risk of client secret leaking
  description = "The OAuth2 Client secret for the previously set up IdP Credential"
  type = string
}

###

variable "grr_adminui_idp_authorization_endpoint" {
  description = "The OAuth2 authorization endpoint for the previously set up IdP Credential"
  type = string
}

variable "grr_adminui_idp_client_id" {
  description = "The OAuth2 Client id for the previously set up IdP Credential"
  type = string
}

variable "grr_adminui_idp_client_secret" {
  # We rely on the redirect_uri being hard to compromise and accept the risk of client secret leaking
  description = "The OAuth2 Client secret for the previously set up IdP Credential"
  type = string
}

variable "grr_adminui_idp_issuer" {
  description = "The OAuth2 issuer for the previously set up IdP Credential"
  type = string
}

variable "grr_adminui_idp_token_endpoint" {
  description = "The OAuth2 token endpoint for the previously set up IdP Credential"
  type = string
}

variable "grr_adminui_idp_user_info_endpoint" {
  description = "The OAuth2 user info endpoint for the previously set up IdP Credential"
  type = string
}

###

# variable "grr_adminui_machine_type" {
#   description = "The machine type to spawn for the adminui instance group"
#   default     = "n1-standard-1"
# }

# variable "grr_adminui_external_hostname" {
#   description = "This is the hostname that users will access the GRR AdminUI from. Usually the DNS name configured."
# }

#  variable "grr_adminui_ssl_cert_path" {	
#   description = "File path to public SSL certificate in PEM format"	
# }	

#  variable "grr_adminui_ssl_cert_private_key" {	
#   description = "The private key for the SSL in PEM format"	
# }

variable "_admin_ui_backend_service_name" {
  description = "Needed to break dependency cycle. Do not change."
  default     = "grr-adminui"
  type = string
}

variable "grr_adminui_username" {
  description = "The GRR adminUI username"
  default     = "root"
  type = string
}

variable "grr_ca_cn" {
  description = "Common name for internal CA"
  type = string
  default = locals.fqdn
}

# variable "frontend_cn" {
#   description = "Common name to use frotend certificate"
# }

variable "grr_ca_org" {
  description = "Organization for internal CA"
  type = string
}

variable "grr_ca_country" {
  description = "Country for internal CA"
  type = string
}

variable "frontend_rsa_key_length" {
  description = "The number of bits of entropy to use for the RSA algrorithm use for the signing key"
  default = 2048
  type = number
}

variable "web_dns_zone_id" {
  description = "The id of the managed DNS zone for GRR"
  type = string
}

variable "private_dns_domain" {
  description = "The private domain to use as a namespace for internal DNS for GRR container private communications"
  type = string
}

variable "dns_default_ttl" {
  description = "The default TTL for DNS records in seconds"
  default     = 60
  type = number
}

variable "grr_frontend_image" {
  description = "Docker image to run for GRR frontend"
  type = string
  default = locals.default_grr_image
}

variable "grr_frontend_image_tag" {
  description = "Docker image tag to pull of image specified by grr_frontend_image"
  type = string
  default = locals.default_grr_image_tag
}

variable "grr_frontend_target_size" {
  description = "The number of GRR Frontend instances that should always be running"
  default     = 3
  type = number
}

# variable "grr_frontend_machine_type" {
#   description = "The machine type to spawn for the frontend instance group"
#   default     = "n1-standard-1"
# }

variable "database_image" {
  description = "Docker image to run for the GRR database"
  default     = "mysql"
  type = string
}

variable "database_version" {
  description = "The version of MySQL to use for the task"
  default     = "5.7"
  type = string
}

# variable "database_tier" {
#   description = "Database deployment tier (machien type)"
#   default     = "db-n1-standard-4"
# }

# variable "storage_access_logs_bucket_name" {
#   description = "Name of the GCS bucket that will store access logs. Needs to be globally unique"
# }

# Note: I dont think we will use this; we will check out an efs mount
# variable "client_installers_bucket_name" {
#   description = "Name of the GCS bucket that will store generated grr client installers. Needs to be globally unique"
# }

# variable "gcs_bucket_location" {
#   description = "Location of buckets to be created"
#   default     = "US"
# }

variable "grr_worker_image" {
  description = "Docker image to run for GRR worker"
  type = string
  default = locals.default_grr_image
}

variable "grr_worker_image_tag" {
  description = "Docker image tag to pull of image specified by grr_worker_image"
  type = string
  default = locals.default_grr_image_tag
}

# Note: we may or may not use this.
variable "grr_worker_monitoring_port" {
  description = "GRR worker monitoring stats port"
  default     = 5222
  type = number
}

variable "grr_worker_target_size" {
  description = "The number of GRR worker instances that should always be running"
  default     = 5
  type = number
}

# variable "grr_worker_machine_type" {
#   description = "The machine type to spawn for the worker instance group"
#   default     = "n1-standard-1"
# }

###

variable "vpc_egress_security_group_id" {
  description = "The ID of the security group which permits general egress (ingress only from self, egress usually to 0.0.0.0) for the VPC"
  type = string
}

variable "service_subnet_ids" {
  description = "The list of subnet ids to which the service's task containers may be attached"
  type = list(string)
}

variable "service_vpc_id" {
  description = "The id of the VPC into which the tasks of the service will be deployed"
  type = string
}

variable "ecs_cluster_name" {
  description = "The name of the ecs cluster to deploy the service to"
  type = string
}

variable "ecs_capacity_provider_name" {
  description = "The name of the ecs capacity provider to provide capacity for the ecs service"
  type = string
}

variable "grr_db_name" {
  description = "The name of the database defined for grr in the mysql service"
  type = string
  default = "grr"
}

variable "grr_db_username" {
  description = "The user name of user grr uses to access the database"
  type = string
  default = "grr"
}

variable "grr_db_port" {
  description = "The port number used to serve the mysql database"
  type = number
  default = 3306
}

variable "grr_db_password" {
  description = "The "
  type = string
  default = random_string.grr_db_root_password.result
}

variable "grr_db_root_password" {
  description = "The user name of user grr uses to access the database"
  type = string
  default = random_string.grr_db_user_password.result
}

variable "grr_adminui_password" {
  description = "The initial password used to log in to grr as the admin user"
  type = string
  default = random_string.grr_adminui_password.result
}

# TODO: add smtp settings (we can use SES! \o/)

# TODO: we may need to put the config as a unified thing in one place (config efs) so the ui (or api?) can update it, but all other things would have R/O access

# variable "ecs_container_instance_security_group_id" {
#   description = ""
#   type = string
# }
