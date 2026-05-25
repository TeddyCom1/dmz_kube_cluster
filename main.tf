terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.66.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.7.0"
    }
  }
  backend "http" {
    address        = "https://git.home.mongernet.com/api/packages/ci-bot/terraform/state/dmz-kube-cluster"
    lock_address   = "https://git.home.mongernet.com/api/packages/ci-bot/terraform/state/dmz-kube-cluster/lock"
    unlock_address = "https://git.home.mongernet.com/api/packages/ci-bot/terraform/state/dmz-kube-cluster/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
  }
  required_version = ">= 1.3.0"
}

provider "proxmox" {
  endpoint = var.proxmox_api_url
  insecure = true
  # Credentials via PROXMOX_VE_API_TOKEN env var.
  # Format: "user@realm!tokenid=<uuid-secret>"
}

# ─── Cluster secrets (generated once, shared across both module calls) ────────

resource "talos_machine_secrets" "this" {}

# ─── Control plane nodes ──────────────────────────────────────────────────────

module "controlplane" {
  source = "git::https://github.com/TeddyCom1/talos-proxmox-module.git"

  node_type       = "controlplane"
  cluster_name    = var.cluster_name
  machine_secrets = talos_machine_secrets.this
  talos_version   = var.talos_version
  image           = proxmox_download_file.talos_image.id
  vlan_id         = var.vlan_id

  nodes = {
    cp0 = { name = "dmz-cp-0", target_node = var.proxmox_node_name }
  }

  cores     = 2
  memory    = 4096
  disk_size = 20

  depends_on = [ proxmox_download_file.talos_image ]
}

# Bootstrap the cluster on the first control plane node after configs are applied.
resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = module.controlplane.node_ips["cp0"]

  depends_on = [module.controlplane]
}

# ─── Worker nodes ─────────────────────────────────────────────────────────────

module "workers" {
  source = "git::https://github.com/TeddyCom1/talos-proxmox-module.git"

  node_type        = "worker"
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${module.controlplane.node_ips["cp0"]}:6443"
  machine_secrets  = talos_machine_secrets.this
  talos_version    = var.talos_version
  image            = proxmox_download_file.talos_image.id
  vlan_id          = var.vlan_id

  nodes = {
    w0 = { name = "dmz-worker-0", target_node = var.proxmox_node_name }
  }

  cores     = 2
  memory    = 4096
  disk_size = 20

  depends_on = [talos_machine_bootstrap.this, proxmox_download_file.talos_image]
}

resource "proxmox_download_file" "talos_image" {
  content_type            = "iso"
  datastore_id            = "local"
  node_name               = var.proxmox_node_name
  url                     = "https://factory.talos.dev/image/${var.talos_image_factory_id}/v${var.talos_version}/nocloud-amd64.raw.xz"
  decompression_algorithm = "zst"
  file_name               = "talos-v${var.talos_version}-nocloud-amd64.img"
  overwrite               = false
}


# ─── Outputs ──────────────────────────────────────────────────────────────────

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = module.controlplane.node_ips["cp0"]

  depends_on = [talos_machine_bootstrap.this]
}

output "kubeconfig" {
  value     = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive = true
}
