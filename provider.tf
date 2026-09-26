terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# 1. Vault Provider (Inherits VAULT_ADDR and VAULT_TOKEN from environment)
provider "vault" {
  address = "https://vault.naidu72.info"
}

# 2. Read Secrets from Vault KV-v2
data "vault_kv_secret_v2" "oci_creds" {
  mount = "kv"
  name  = "oci/credentials"
}

# 3. Configure OCI Provider using Vault Secret Data
provider "oci" {
  tenancy_ocid     = data.vault_kv_secret_v2.oci_creds.data["tenancy_ocid"]
  user_ocid        = data.vault_kv_secret_v2.oci_creds.data["user_ocid"]
  fingerprint      = data.vault_kv_secret_v2.oci_creds.data["fingerprint"]
  private_key      = data.vault_kv_secret_v2.oci_creds.data["private_key"]
  region           = data.vault_kv_secret_v2.oci_creds.data["region"]
}

# Expose compartment_ocid for downstream resources
locals {
  compartment_ocid = data.vault_kv_secret_v2.oci_creds.data["compartment_ocid"]
  tenancy_ocid     = data.vault_kv_secret_v2.oci_creds.data["tenancy_ocid"]
}
