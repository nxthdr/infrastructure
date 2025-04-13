# Documentation

## Deploy Docker Containers

To sync the configuration files:

```sh
make sync-config
```

To sync and apply the configuration:

```sh
make apply
```

## Deploy Network Configuration

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
