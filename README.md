# dmz_kube_cluster

Terraform root module that deploys a 3-control-plane + 2-worker Talos Kubernetes cluster in the DMZ network using the [`kube-talos-node-module`](../kube-talos-node-module).

## What gets created

| Resource | Count | Details |
|---|---|---|
| Proxmox VMs | 5 | 3 control plane (`dmz-cp-0/1/2`), 2 workers (`dmz-worker-0/1`) |
| Talos machine configs | 5 | Auto-generated and applied per node |
| Cluster bootstrap | 1 | Runs on `cp0` after all control plane configs are applied |
| Kubeconfig | 1 | Retrieved and exposed as a sensitive output |

## Prerequisites

- Proxmox VE with the Talos ISO uploaded (`local:iso/talos-vX.Y.Z-amd64.iso`)
- DHCP reservations matching the IPs in `main.tf` for all 5 nodes
- A Proxmox API token with permission to create and manage VMs
- Terraform >= 1.3.0

## Setup

### 1. Proxmox credentials

Set these environment variables before running Terraform:

```bash
export PROXMOX_API_TOKEN_ID="terraform@pam!mytoken"
export PROXMOX_API_TOKEN_SECRET="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

### 2. Configure variables

Create a `terraform.tfvars` file:

```hcl
proxmox_api_url  = "https://pve.local:8006/api2/json"
cluster_endpoint = "https://192.168.10.10:6443"
talos_version    = "v1.9.5"
talos_iso_image  = "local:iso/talos-v1.9.5-amd64.iso"
vlan_id          = 10
```

### 3. Update node IPs and Proxmox host assignments

Edit the `nodes` maps in `main.tf` to match your DHCP reservations and PVE node names:

```hcl
# Control plane
cp0 = { name = "dmz-cp-0", target_node = "pve0", ip_address = "192.168.10.10" }

# Workers
w0 = { name = "dmz-worker-0", target_node = "pve0", ip_address = "192.168.10.20" }
```

## Deploy

```bash
terraform init
terraform plan
terraform apply
```

On first apply, Terraform will:
1. Create all 5 VMs booted from the Talos ISO
2. Generate and apply machine configs to each node over the Talos maintenance API
3. Bootstrap the cluster on `cp0`
4. Apply worker configs so they join the cluster
5. Retrieve the kubeconfig

## Get the kubeconfig

```bash
terraform output -raw kubeconfig > ~/.kube/dmz.yaml
export KUBECONFIG=~/.kube/dmz.yaml
kubectl get nodes
```

## Variables

| Name | Description | Default |
|---|---|---|
| `proxmox_api_url` | Proxmox API URL, e.g. `https://pve.local:8006/api2/json`. | — |
| `cluster_endpoint` | Talos cluster API endpoint, e.g. `https://192.168.10.10:6443`. | — |
| `talos_version` | Talos version, e.g. `v1.9.5`. | — |
| `talos_iso_image` | Proxmox path to the Talos ISO, e.g. `local:iso/talos-v1.9.5-amd64.iso`. | — |
| `cluster_name` | Talos cluster name. | `"dmz"` |
| `vlan_id` | VLAN tag for all cluster nodes. `-1` for untagged. | `-1` |
