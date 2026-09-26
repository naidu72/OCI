# VCN, internet gateway, subnet and network security groups. All of these are free.

resource "oci_core_vcn" "main" {
  compartment_id = local.compartment_ocid
  display_name   = "${var.project}-vcn"
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = "appvcn"
}

resource "oci_core_internet_gateway" "main" {
  compartment_id = local.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project}-igw"
  enabled        = true
}

resource "oci_core_route_table" "public" {
  compartment_id = local.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project}-public-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main.id
  }
}

# The subnet-level list only allows egress and path-MTU discovery; service ports are opened by the NSGs below.
resource "oci_core_security_list" "public" {
  compartment_id = local.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project}-public-sl"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "1" # ICMP
    icmp_options {
      type = 3
      code = 4
    }
  }

  ingress_security_rules {
    source   = var.vcn_cidr
    protocol = "1"
    icmp_options {
      type = 3
    }
  }
}

# Free-tier-only accounts can't create NAT gateways, so the VMs sit in a public subnet
# and rely on NSGs: only the load balancer can reach port 80 and only the VMs can reach 5432.
resource "oci_core_subnet" "public" {
  compartment_id    = local.compartment_ocid
  vcn_id            = oci_core_vcn.main.id
  display_name      = "${var.project}-public-subnet"
  cidr_block        = var.subnet_cidr
  dns_label         = "public"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.public.id]
}

resource "oci_core_network_security_group" "lb" {
  compartment_id = local.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project}-lb-nsg"
}

resource "oci_core_network_security_group_security_rule" "lb_http_in" {
  network_security_group_id = oci_core_network_security_group.lb.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source_type               = "CIDR_BLOCK"
  source                    = "0.0.0.0/0"
  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
}

resource "oci_core_network_security_group" "app" {
  compartment_id = local.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.project}-app-nsg"
}

resource "oci_core_network_security_group_security_rule" "app_http_from_lb" {
  network_security_group_id = oci_core_network_security_group.app.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source_type               = "NETWORK_SECURITY_GROUP"
  source                    = oci_core_network_security_group.lb.id
  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
}

resource "oci_core_network_security_group_security_rule" "app_postgres_between_vms" {
  network_security_group_id = oci_core_network_security_group.app.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source_type               = "NETWORK_SECURITY_GROUP"
  source                    = oci_core_network_security_group.app.id
  tcp_options {
    destination_port_range {
      min = 5432
      max = 5432
    }
  }
}

resource "oci_core_network_security_group_security_rule" "app_ssh" {
  network_security_group_id = oci_core_network_security_group.app.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source_type               = "CIDR_BLOCK"
  source                    = var.admin_cidr
  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}
