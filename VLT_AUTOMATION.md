# VLT Server Automation Guide

This guide explains how to use the automated VLT server provisioning system.

## Overview

The VLT infrastructure is now managed declaratively through Terraform, with **inventory.yml as the source of truth**. When you add or remove a server from the inventory, Terraform will automatically create or destroy the corresponding infrastructure.

## Architecture

```
inventory.yml (source of truth)
    ↓
render_terraform.py (generates Terraform configs)
    ↓
vlt-infrastructure.tf (manages Vultr servers + DNS)
    ↓
Vultr API + Porkbun API
```

## Prerequisites

### 1. Add Vultr API Key to Secrets

Edit your secrets file:
```bash
make edit-secrets
```

Add the following:
```yaml
vultr_api_key: "YOUR_VULTR_API_KEY"
```

### 2. Ensure SSH Keys in Vultr

Make sure you have SSH keys uploaded to your Vultr account with the name `nxthdr` (or update the `vultr_ssh_key_names` variable in `terraform/variables.tf`).

### 3. Verify Porkbun Credentials

Ensure your Porkbun API credentials are already in the secrets file:
```yaml
porkbun_api_key: "YOUR_PORKBUN_API_KEY"
porkbun_secret_api_key: "YOUR_PORKBUN_SECRET_KEY"
```

## Adding a New VLT Server

### Step 1: Update Inventory

Edit `inventory/inventory.yml` and add your new server to the `vlt.hosts` section:

```yaml
vlt:
  hosts:
    vltatl01:
      ansible_host: atl01.vlt.infra.nxthdr.dev
      uniprobe0: 2a0e:97c0:8a3::/48
    vltcdg01:
      ansible_host: cdg01.vlt.infra.nxthdr.dev
      uniprobe0: 2a0e:97c0:8a4::/48
    vltfra01:
      ansible_host: fra01.vlt.infra.nxthdr.dev
      uniprobe0: 2a0e:97c0:8a5::/48
    vltlax01:  # NEW SERVER
      ansible_host: lax01.vlt.infra.nxthdr.dev
      uniprobe0: 2a0e:97c0:8a6::/48
  vars:
    ansible_user: nxthdr
```

**Important naming convention:**
- Hostname format: `vlt{location}{number}` (e.g., `vltlax01`)
- The location code (3 letters) is extracted from the hostname
- The location code must match a valid Vultr region

**Common Vultr regions:**
- `atl` - Atlanta
- `cdg` - Paris
- `fra` - Frankfurt
- `lax` - Los Angeles
- `mia` - Miami
- `nrt` - Tokyo
- `sjc` - Silicon Valley
- `syd` - Sydney
- `yto` - Toronto

### Step 2: Render Terraform Configuration

```bash
make render-terraform
```

This generates `terraform/vlt-infrastructure.tf` with your new server included.

### Step 3: Review Terraform Plan

```bash
cd terraform
terraform plan
```

Review the changes. You should see:
- 1 new Vultr instance
- 2 new Porkbun DNS records (A and AAAA)

### Step 4: Apply Infrastructure Changes

```bash
terraform apply
```

Or from the root:
```bash
# This will render configs AND apply Terraform
make apply
```

### Step 5: Wait for Server to Boot

The server will take 2-5 minutes to provision and boot. You can check status:

```bash
terraform output vlt_servers
```

### Step 6: Run Ansible Playbooks

Once the server is accessible via SSH, run the setup playbooks:

```bash
# Install user and SSH keys (requires root password from Vultr)
ansible-playbook -k -i inventory/ -e "base_dir=$(pwd)" -e @secrets/secrets.yml \
  -e 'ansible_user=root' --vault-password-file .password \
  playbooks/install-user.yml --limit vltlax01

# Install Docker
ansible-playbook -i inventory/ --ask-become-pass \
  playbooks/install-docker.yml --limit vltlax01

# Install hsflowd
ansible-playbook -i inventory/ --ask-become-pass \
  playbooks/install-hsflowd.yml --limit vltlax01

# Install rsyslog
ansible-playbook -i inventory/ --ask-become-pass \
  playbooks/install-rsyslog.yml --limit vltlax01

# Install BIRD
ansible-playbook -i inventory/ --ask-become-pass \
  playbooks/install-bird.yml --limit vltlax01

# Install VLT network configuration
ansible-playbook -i inventory/ --ask-become-pass \
  playbooks/install-vlt-network.yml --limit vltlax01
```

### Step 7: Create BIRD Configuration

You need to manually create the BIRD configuration file for the new server:

```bash
mkdir -p networks/vltlax01/bird
```

Create `networks/vltlax01/bird/bird.conf` based on the template from other servers. You'll need:
- Router ID: Use the server's IPv4 address (from `terraform output vlt_servers`)
- Link-local address: Get from Vultr console or server (usually `fe80::fc00:5ff:fe*`)
- BGP local address: Use the server's IPv6 address

### Step 8: Deploy Configuration and Containers

```bash
# Render all configs
make render-config

# Sync BIRD configuration
make sync-bird

# Deploy Docker containers
make apply
```

### Step 9: Update Saimprowler

Edit `templates/config/core/coreams01/cronjobs/saimprowler/saimprowler.sh` and add the new server to the saimiris client command (line 41):

```bash
docker run --rm --name cron-saimprowler-saimiris --network=host \
    -v $SCRIPTPATH/config/config.yml:/config/config.yml \
    -v $SCRIPTPATH/data/probes.csv:/data/probes.csv \
    $DOCKER_IMAGE_SAIMIRIS \
    client --config /config/config.yml --probes-file=/data/probes.csv \
    vltatl01:[2a0e:97c0:8a0::10],vltcdg01:[2a0e:97c0:8a0::10],vltfra01:[2a0e:97c0:8a0::10],vltlax01:[2a0e:97c0:8a0::10]
```

Then sync the config:
```bash
make sync-config
```

## Removing a VLT Server

### Step 1: Remove from Inventory

Edit `inventory/inventory.yml` and remove the server from `vlt.hosts`.

### Step 2: Render and Apply

```bash
make render-terraform
cd terraform
terraform plan  # Review destruction
terraform apply
```

This will:
- Destroy the Vultr instance
- Remove the DNS records

### Step 3: Clean Up Configuration Files

```bash
# Remove BIRD config
rm -rf networks/vltlax01

# Remove generated Terraform file
rm terraform/vltlax01.tf

# Update saimprowler.sh to remove the server
```

## Troubleshooting

### Server Not Accessible After Creation

1. Check Terraform outputs:
   ```bash
   terraform output vlt_servers
   ```

2. Verify DNS propagation:
   ```bash
   dig lax01.vlt.infra.nxthdr.dev
   ```

3. Check server status in Vultr console

### Terraform Errors

**"SSH key not found"**
- Ensure you have SSH keys uploaded to Vultr with the correct name
- Update `vultr_ssh_key_names` in `terraform/variables.tf` if needed

**"Region not available"**
- Check valid Vultr regions: https://www.vultr.com/api/#operation/list-regions
- Update the hostname to use a valid 3-letter region code

**"Plan not available in region"**
- Some plans are not available in all regions
- Override the `plan` variable in the module call if needed

### DNS Not Updating

- Porkbun DNS updates can take a few minutes
- Verify credentials in secrets file
- Check Porkbun API logs

## Advanced Configuration

### Custom Server Plan

Edit `templates/terraform/vlt-infrastructure.tf.j2` and uncomment the plan override:

```hcl
module "vlt_server" {
  source   = "./modules/vlt-server"
  for_each = local.vlt_servers

  hostname     = each.key
  region       = each.value.region
  ssh_key_ids  = local.ssh_key_ids

  plan = "vc2-2c-4gb"  # Larger instance
}
```

### Different OS

Override the `os_id` parameter:
```hcl
os_id = 2625  # Debian 13 x64 trixie (default)
# os_id = 2136  # Debian 12 x64 bookworm
# os_id = 1743  # Ubuntu 22.04 LTS
# os_id = 2284  # Ubuntu 24.04 LTS
```

Find OS IDs: https://www.vultr.com/api/#operation/list-os

## Benefits of This Approach

✅ **Single source of truth**: Inventory drives everything
✅ **Idempotent**: Safe to re-run
✅ **Declarative**: Describe desired state, not steps
✅ **Traceable**: Terraform state tracks all resources
✅ **Reversible**: Easy to destroy infrastructure
✅ **Automated DNS**: No manual Porkbun configuration
✅ **Version controlled**: All changes in Git

## Next Steps

Future improvements could include:
- Automated BIRD config generation from Terraform outputs
- Automatic Ansible playbook execution after server creation
- Integration with monitoring/alerting on server creation
- Automated saimprowler.sh updates
