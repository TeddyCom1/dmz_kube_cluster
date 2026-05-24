# dmz_kube_cluster

Terraform root module that deploys a Talos Kubernetes cluster in the DMZ network using the [`kube-talos-node-module`](https://github.com/TeddyCom1/talos-proxmox-module).

## What gets created

| Resource | Count | Details |
|---|---|---|
| Proxmox VMs | 2 | 1 control plane (`dmz-cp-0`), 1 worker (`dmz-worker-0`) |
| Talos machine configs | 2 | Auto-generated and applied per node |
| Cluster bootstrap | 1 | Runs on `cp0` after the control plane config is applied |
| Kubeconfig | 1 | Retrieved and exposed as a sensitive output |

Node IPs are assigned by DHCP automatically — no IP addresses are hardcoded anywhere in this configuration.

## Prerequisites

- Proxmox VE with a Talos ISO uploaded — **must include the `qemu-guest-agent` system extension**. Generate a custom image at [factory.talos.dev](https://factory.talos.dev/), enable the `qemu-guest-agent` extension, and upload the resulting ISO to Proxmox. Update `talos_iso_image` in `vars/prod.tfvars` to point to it.
- A Proxmox API token with permission to create and manage VMs
- Terraform >= 1.3.0

## Setup

### 1. Gitea backend credentials

Terraform state is stored in a Gitea HTTP backend. Export these before running `terraform init`:

```bash
export TF_HTTP_USERNAME="<Gitea username>"
export TF_HTTP_PASSWORD="<gitea-personal-access-token>"  # requires package read+write scope
```

### 2. Proxmox credentials

```bash
export PROXMOX_API_TOKEN_ID="terraform@pam!mytoken"
export PROXMOX_API_TOKEN_SECRET="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

### 3. Configure variables

Edit `vars/prod.tfvars` (or create a `terraform.tfvars`):

```hcl
proxmox_api_url = "https://pve.local:8006/api2/json"
talos_version   = "v1.9.5"
talos_iso_image = "local:iso/talos-v1.9.5-amd64.iso"  # must have qemu-guest-agent extension
cluster_name    = "dmz"
vlan_id         = 10
```

No `cluster_endpoint` is required — it is automatically derived from the control plane node's DHCP-assigned IP at apply time.

### 4. Adjust node names and Proxmox host assignments (optional)

The `nodes` maps in `main.tf` only need a VM name and the Proxmox node to place the VM on:

```hcl
# Control plane
cp0 = { name = "dmz-cp-0", target_node = "pve0" }

# Workers
w0 = { name = "dmz-worker-0", target_node = "pve0" }
```

## Deploy

```bash
terraform init
terraform plan -var-file=vars/prod.tfvars
terraform apply -var-file=vars/prod.tfvars
```

On first apply, Terraform will:
1. Create all VMs booted from the Talos ISO
2. Wait for each VM's QEMU guest agent to report its DHCP-assigned IP
3. Generate and apply machine configs to each node over the Talos maintenance API
4. Bootstrap the cluster on `cp0`
5. Apply worker configs so they join the cluster
6. Retrieve the kubeconfig

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
| `talos_version` | Talos version, e.g. `v1.9.5`. | — |
| `talos_iso_image` | Proxmox path to the Talos ISO (must include `qemu-guest-agent` extension). | — |
| `cluster_name` | Talos cluster name. | `"dmz"` |
| `vlan_id` | VLAN tag for all cluster nodes. `-1` for untagged. | `-1` |
