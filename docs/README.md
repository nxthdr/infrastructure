# Documentation

First check out the [inventory](../inventory/inventory.yml) file (`inventory/inventory.yml`) which contains the list of servers and their roles.
There are currently four roles:

* `core` - Core servers
* `ixp`  - IXP servers
* `scw`  - Scaleway servers (used by the core)
* `vlt`  - Probing servers

## Vault

All secrets of the infrastructure are stored as a Ansible Vault secret that can be found [here](../secrets/secrets.yml) (`secrets/secrets.yml`).

The render scripts and Ansible playbooks are using those secrets to configure the servers. To make them work the first time, you need to create in the root of the repository a file called `.password` with the vault password. This file is added to the `.gitignore` file, so it won't be pushed to the repository.

```sh
echo "<PASSWORD>" > .password
```

Note: several Ansible playbooks are running with superuser privileges, so you need to prompt the root password (called the "BECOME password" by Ansible).

## Deploy Docker Containers

All servers are running Docker containers. You can find the configuration in the `templates` [directory](../templates/).

The configuration is rendered dynamically using the [render](../render/) python scripts.
The `ixp`  and `vlt` servers are using the same configuration within a role, but with different parameters.

* `render_config.py` - Templating the configuration files
* `render_terraform.py` - Templating the terraform files

The configuration files are rendered in a `.rendered` directory. This directory contain plaintext passwords, so ignored by git and not pushed to the repository.

The terraform files are rendered in a `terraform` directory. This directory is used to deploy the Docker containers. Those files are not ignored by git. When a file is rendered, there is a warning in the top file to indicate that the file is generated and should not be modified directly.

To template the configuration and terraform files:

```sh
make template
```

Once rendererd, the configuration files needs to be synced to the servers. To template and sync the configuration files in to the servers:

```sh
make sync-config
```

Finally, if we changed the terraform files, we need to apply the changes. To template, sync and apply the entire configuration:

```sh
make apply
```

Note that if you want to apply a configuration change that did not changed the terraform files, you can simply run, an apply will not work. The simplest is to restart the container on the server directly:

```sh
docker restart <CONTAINER>
```

## Deploy Network Configuration

Pretty much all servers are running BIRD to announce routes. The configuration can be found in the `networks` [directory](../networks/).

To sync the network configuration files:

```sh
make sync-bird
```

## Provisioning

### IXP servers

* user
* rsyslog
* hsflowd
* docker
* wireguard
* bird
* alloy, cadvisor

### Probing servers

* user
* rsyslog
* hsflowd
* docker
* vlt-interfaces
* alloy, cadvisor
* saimiris

## Manual Configuration

### Aliases

In core, we have a few aliases to make it easier to manage the infrastructure.

```sh
alias rpk="docker exec -ti redpanda rpk"
```

### Ip6tables

By default, Docker network bridges are not accessible from the outside world.

In Core, we simply accept any traffic from the DMZ network.

```sh
ip6tables -I DOCKER-USER -d 2a06:de00:50:cafe:100::/80 -j ACCEPT
```

### Grafana admin password

Right now we don't have a way to set the Grafana admin password automatically.

```sh
docker exec -ti grafana grafana cli admin reset-admin-password  <PASSWORD>
```
