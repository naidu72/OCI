output "app_url" {
  description = "Public entry point (load balancer)."
  value       = "http://${oci_load_balancer_load_balancer.main.ip_address_details[0].ip_address}"
}

output "vm_public_ips" {
  value = { for k, vm in oci_core_instance.node : k => vm.public_ip }
}

output "ssh_commands" {
  value = { for k, vm in oci_core_instance.node : k => "ssh ubuntu@${vm.public_ip}" }
}

output "image" {
  value = data.oci_core_images.ubuntu_arm.images[0].display_name
}
