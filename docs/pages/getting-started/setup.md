# Environment Setup

This guide will help you set up your local environment to work with the nxthdr infrastructure.

## Prerequisites

### Required Tools

1. **Python 3.11+** with [uv](https://docs.astral.sh/uv/) package manager
2. **Ansible** 2.9+
3. **Terraform** 1.0+
4. **SSH access** to infrastructure servers
5. **Vault password** (contact admin@nxthdr.dev)

### Installation

=== "macOS"

    ```bash
    # Install Homebrew if not already installed
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Install required tools
    brew install ansible terraform uv
    ```

=== "Linux (Ubuntu/Debian)"

    ```bash
    # Install Ansible
    sudo apt update
    sudo apt install ansible
    
    # Install Terraform
    wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt update && sudo apt install terraform
    
    # Install uv
    curl -LsSf https://astral.sh/uv/install.sh | sh
    ```

=== "Linux (Fedora/RHEL)"

    ```bash
    # Install Ansible
    sudo dnf install ansible
    
    # Install Terraform
    sudo dnf install -y dnf-plugins-core
    sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
    sudo dnf install terraform
    
    # Install uv
    curl -LsSf https://astral.sh/uv/install.sh | sh
    ```

## Repository Setup

### 1. Clone the Repository

```bash
git clone https://github.com/nxthdr/infrastructure.git
cd infrastructure
```

### 2. Configure Vault Password

Create a `.password` file with the Ansible Vault password:

```bash
echo "YOUR_VAULT_PASSWORD" > .password
chmod 600 .password
```

!!! warning "Security"
    The `.password` file is gitignored and should never be committed. Keep it secure!

### 3. Verify Vault Access

Test that you can decrypt secrets:

```bash
make edit-secrets
```

This should open the secrets file in your editor. Close without making changes.

### 4. Configure SSH Access

Ensure you have SSH access to the infrastructure servers:

```bash
# Test connection to a server
ssh nxthdr@ams01.core.infra.nxthdr.dev

# If using SSH keys, add to your SSH config (~/.ssh/config)
Host *.infra.nxthdr.dev
    User nxthdr
    IdentityFile ~/.ssh/id_ed25519
```

### 5. Initialize Terraform

```bash
cd terraform
terraform init
cd ..
```

## Verify Setup

Run a dry-run to verify everything is configured correctly:

```bash
# Render templates
make render

# Check what would be synced (dry-run)
ansible-playbook -i inventory/ playbooks/sync-config.yml --check

# Check Terraform plan
terraform -chdir=./terraform plan
```

If all commands complete without errors, your environment is ready!

## Optional: Python Development Environment

If you plan to modify the rendering scripts:

```bash
cd render
uv sync
cd ..
```

This creates a virtual environment with all dependencies for the rendering scripts.

## Troubleshooting

### Vault Decryption Fails

```
ERROR! Decryption failed
```

**Solution**: Verify your `.password` file contains the correct vault password.

### SSH Connection Refused

```
ssh: connect to host ... port 22: Connection refused
```

**Solution**: 
- Verify you have network access to the servers
- Check your SSH key is authorized
- Contact admin@nxthdr.dev for access

### Terraform Provider Issues

```
Error: Failed to query available provider packages
```

**Solution**: Run `terraform init` in the `terraform/` directory.

### Ansible Module Not Found

```
ERROR! couldn't resolve module/action 'ansible.posix.synchronize'
```

**Solution**: Install the required Ansible collection:

```bash
ansible-galaxy collection install ansible.posix
```

## Next Steps

Now that your environment is set up:

- Follow the [Quick Start guide](quick-start.md) to make your first deployment
- Review [Common Tasks](../guides/common-tasks.md) for typical operations
- Explore the [Reference documentation](../reference/architecture.md) for deeper understanding
