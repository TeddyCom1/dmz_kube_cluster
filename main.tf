terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 3.0, 3.0.2-rc07"
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
  pm_api_url = var.proxmox_api_url
  # Credentials via PROXMOX_API_TOKEN_ID and PROXMOX_API_TOKEN_SECRET env vars.
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
  iso_image       = var.talos_iso_image
  vlan_id         = var.vlan_id

  nodes = {
    cp0 = { name = "dmz-cp-0", target_node = "pve0" }
  }

  cores     = 2
  memory    = 4096
  disk_size = 20
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
  iso_image        = var.talos_iso_image
  vlan_id          = var.vlan_id

  nodes = {
    w0 = { name = "dmz-worker-0", target_node = "pve0" }
  }

  cores     = 2
  memory    = 4096
  disk_size = 20

  depends_on = [talos_bootstrap.this]
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = module.controlplane.node_ips["cp0"]

  depends_on = [talos_bootstrap.this]
}

output "kubeconfig" {
  value     = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive = true
}
