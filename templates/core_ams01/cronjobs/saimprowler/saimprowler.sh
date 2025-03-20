#!/bin/bash

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

DOCKER_IMAGE_PROWL=ghcr.io/nxthdr/prowl:main
DOCKER_IMAGE_SAIMIRIS=ghcr.io/nxthdr/saimiris:main

# Always Docker pull the latest image
docker pull $DOCKER_IMAGE_PROWL
docker pull $DOCKER_IMAGE_SAIMIRIS

# Probes generation
docker run --rm --name cron-saimprowler-prowl \
    -v $SCRIPTPATH/data/targets.csv:/data/targets.csv \
    $DOCKER_IMAGE_PROWL \
    --tool traceroute --mapper sequential \
    /data/targets.csv > $SCRIPTPATH/data/probes.csv

# Probes execution
docker run --rm --name cron-saimprowler-saimiris --network=host \
    -v $SCRIPTPATH/config/config.yml:/config/config.yml \
    -v $SCRIPTPATH/data/probes.csv:/data/probes.csv \
    $DOCKER_IMAGE_SAIMIRIS \
    client --config /config/config.yml --probes-file=/data/probes.csv d2nm65zx8n,j7fph85rgr
