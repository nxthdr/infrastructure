# Infrastructure

This directory contains the infrastructure configuration for [nxthdr](https://nxthdr.dev).

## Usage

To sync the configuration files:

```sh
make sync-config
```

To sync and apply the configuration:

```sh
make apply
```

## Manual Configuration

### Aliases

In core, we have a few aliases to make it easier to manage the infrastructure.

```sh
alias rpk="docker exec -ti redpanda rpk -X'brokers=2a06:de00:50:cafe:10::103'"
```

### Ip6tables

By default, Docker network bridges are not accessible from the outside world.<br>
In Core, we simply accept any traffic from the DMZ network.

```sh
ip6tables -I DOCKER-USER -d 2a06:de00:50:cafe:100::/80 -j ACCEPT
```
