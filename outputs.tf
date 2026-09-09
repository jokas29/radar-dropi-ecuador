output "public_ip" {
  value       = oci_core_instance.radar.public_ip
  description = "Public IPv4 address of Radar Commerce."
}

output "commerce_url" {
  value       = "https://radar-${replace(oci_core_instance.radar.public_ip, ".", "-")}.sslip.io"
  description = "Expected HTTPS URL after cloud-init finishes and Let's Encrypt succeeds."
}

output "wp_admin_url" {
  value       = "https://radar-${replace(oci_core_instance.radar.public_ip, ".", "-")}.sslip.io/wp-admin/"
  description = "WordPress administration URL."
}

output "wp_admin_user" {
  value       = "radar_admin"
  description = "Temporary WordPress administrator username."
}

output "wp_admin_password" {
  value       = random_password.wp_admin.result
  description = "Temporary WordPress administrator password. Change it after first login."
  sensitive   = false
}
