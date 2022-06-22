# Empty Outputs to comply with https://www.terraform.io/docs/modules/index.html#standard-module-structure

# output "lb_address" {
#   value = "${google_compute_global_address.grr_adminui_lb.address}"
# }

output "grr_user" {
  value = var.grr_adminui_username
}

output "grr_password" {
  value = var.grr_adminui_password
}

# TODO: get this from route 53?
# output "frontend_fqdn" {
#   value = "${google_dns_record_set.frontend.name}"
# }

output "client_fingerprint" {
  value = "${random_id.client_installer_fingerprint.dec}"
}

# TODO: add access controls for lb

# output "frontend_lb_address" {
#   value = "${google_compute_global_address.grr_frontend_lb.address}"
# }

# output "grr_db_ip" {
#   value = "${google_sql_database_instance.grr_db.ip_address.0.ip_address}"
# }

output "grr_db_user" {
  value = "${var.grr_db_username}"
}

output "grr_db_password" {
  value     = "${var.grr_db_user_password}"
  sensitive = true
}

output "grr_db_root_password" {
  value     = "${var.grr_db_root_password}"
  sensitive = true
}

# output "grr_client_installers_bucket" {
#   value = "${google_storage_bucket.client_installers.name}"
# }
