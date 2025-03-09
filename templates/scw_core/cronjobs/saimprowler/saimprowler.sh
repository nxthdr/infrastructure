#!/bin/bash

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

# Always Docker pull the latest image
docker pull ghcr.io/nxthdr/prowl:main
docker pull ghcr.io/nxthdr/saimiris:main

# Probes generation
docker run --rm \
    -v $SCRIPTPATH/data/targets.csv:/data/targets.csv \
    ghcr.io/nxthdr/prowl:main \
    --tool traceroute --mapper sequential \
    /data/targets.csv > $SCRIPTPATH/data/probes.csv

# Probes execution
docker run --rm --network=host \
    -v $SCRIPTPATH/config/config.yml:/config/config.yml \
    -v $SCRIPTPATH/data/probes.csv:/data/probes.csv \
    ghcr.io/nxthdr/saimiris:main \
    client --config /config/config.yml --probes-file=/data/probes.csv d2nm65zx8n,j7fph85rgr
