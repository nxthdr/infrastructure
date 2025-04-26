# Documentation

First check out the [inventory](../inventory/inventory.yml) file (`inventory/inventory.yml`) which contains the list of servers and their roles.
There are currently four roles:

* `core` - Core servers
* `ixp`  - IXP servers
* `scw`  - Scaleway servers (used by the core)
* `vlt`  - Probing servers

## Deploy Docker Containers

All servers are running Docker containers. You can find the configuration in the `templates` directory.

The configuration is rendered dynamically using the [render](../render/) python scripts.
The `ixp`  and `vlt` servers are using the same configuration within a role, but with different parameters.

* `render_config.py` - Templating the configuration files
* `render_terraform.py` - Templating the terraform files

To template the configuration and terraform files:

```sh
make template
```

To template and sync the configuration files:

```sh
make sync-config
```

To template, sync and apply the entire configuration:

```sh
make apply
```

## Deploy Network Configuration

Pretty much all servers are running BIRD to announce routes. The configuration can be found in the `network` directory.

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
