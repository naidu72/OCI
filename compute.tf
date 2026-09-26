# Two Always Free Ampere A1 VMs in separate fault domains. vm-1 bootstraps the database
# primary, vm-2 starts as its streaming standby; both run the full nginx + app stack.

data "oci_identity_availability_domains" "ads" {
  compartment_id = local.tenancy_ocid
}

data "oci_core_images" "ubuntu_arm" {
  compartment_id           = local.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"

  filter {
    name   = "display_name"
    values = ["^Canonical-Ubuntu-24\\.04-aarch64-.*"]
    regex  = true
  }
}

resource "random_password" "postgres" {
  length  = 32
  special = false
}

resource "random_password" "app_db" {
  length  = 32
  special = false
}

resource "random_password" "replication" {
  length  = 32
  special = false
}

locals {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[var.availability_domain_index].name

  nodes = {
    "vm-1" = { ip = cidrhost(var.subnet_cidr, 10), role = "primary", fault_domain = "FAULT-DOMAIN-1" }
    "vm-2" = { ip = cidrhost(var.subnet_cidr, 11), role = "standby", fault_domain = "FAULT-DOMAIN-2" }
  }

  # Every file under app/ is shipped to /opt/app on each VM through cloud-init.
  app_files = {
    for f in fileset("${path.module}/app", "**") : f => filebase64("${path.module}/app/${f}")
    if !strcontains(f, "__pycache__")
  }
}

resource "oci_core_instance" "node" {
  for_each = local.nodes

  compartment_id      = local.compartment_ocid
  availability_domain = local.availability_domain
  fault_domain        = each.value.fault_domain
  display_name        = "${var.project}-${each.key}"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.vm_ocpus
    memory_in_gbs = var.vm_memory_gbs
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_arm.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    private_ip       = each.value.ip
    assign_public_ip = true
    hostname_label   = each.key
    nsg_ids          = [oci_core_network_security_group.app.id]
  }

  availability_config {
    recovery_action = "RESTORE_INSTANCE"
  }

  metadata = {
    ssh_authorized_keys = trimspace(file(pathexpand(var.ssh_public_key_path)))
    user_data = base64gzip(templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
      files = local.app_files
      env = {
        NODE_NAME              = each.key
        NODE_ROLE              = each.value.role
        SELF_IP                = each.value.ip
        PEER_IP                = [for k, n in local.nodes : n.ip if k != each.key][0]
        DB_HOSTS               = join(",", [for n in values(local.nodes) : n.ip])
        POSTGRES_PASSWORD      = random_password.postgres.result
        APP_DB_PASSWORD        = random_password.app_db.result
        REPLICATION_PASSWORD   = random_password.replication.result
        FAILOVER_AFTER_SECONDS = var.failover_after_seconds
        VCN_CIDR               = var.vcn_cidr
      }
    }))
  }

  lifecycle {
    # Don't touch running VMs when Canonical publishes a newer image or app/ changes;
    # rebuild one VM at a time with `terraform apply -replace` instead.
    ignore_changes = [source_details[0].source_id, availability_domain, metadata["user_data"]]
  }
}
