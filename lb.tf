# The one Always Free flexible load balancer (10 Mbps). It health-checks nginx on each VM
# and stops sending traffic to a VM whose stack is down.

resource "oci_load_balancer_load_balancer" "main" {
  compartment_id             = local.compartment_ocid
  display_name               = "${var.project}-lb"
  shape                      = "flexible"
  subnet_ids                 = [oci_core_subnet.public.id]
  network_security_group_ids = [oci_core_network_security_group.lb.id]
  is_private                 = false

  shape_details {
    minimum_bandwidth_in_mbps = 10
    maximum_bandwidth_in_mbps = 10
  }
}

resource "oci_load_balancer_backend_set" "web" {
  load_balancer_id = oci_load_balancer_load_balancer.main.id
  name             = "web"
  policy           = "ROUND_ROBIN"

  health_checker {
    protocol          = "HTTP"
    port              = 80
    url_path          = "/healthz"
    return_code       = 200
    interval_ms       = 10000
    timeout_in_millis = 3000
    retries           = 3
  }
}

resource "oci_load_balancer_backend" "node" {
  for_each = oci_core_instance.node

  load_balancer_id = oci_load_balancer_load_balancer.main.id
  backendset_name  = oci_load_balancer_backend_set.web.name
  ip_address       = each.value.private_ip
  port             = 80
}

resource "oci_load_balancer_listener" "http" {
  load_balancer_id         = oci_load_balancer_load_balancer.main.id
  name                     = "http"
  default_backend_set_name = oci_load_balancer_backend_set.web.name
  port                     = 80
  protocol                 = "HTTP"
}
