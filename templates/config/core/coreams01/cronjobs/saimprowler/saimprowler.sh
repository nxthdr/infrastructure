#!/bin/bash

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

DOCKER_IMAGE_PROWL=ghcr.io/nxthdr/prowl:main
DOCKER_IMAGE_SAIMIRIS=ghcr.io/nxthdr/saimiris:main

# Always Docker pull the latest image
docker pull $DOCKER_IMAGE_PROWL
docker pull $DOCKER_IMAGE_SAIMIRIS

# Targets generation
# Targets are generated from the ipv6-hitlist aliased prefixes list (see https://ipv6hitlist.github.io/)
rm -rf $SCRIPTPATH/data/aliased-prefixes.txt*
rm -rf $SCRIPTPATH/data/targets.csv
curl -s https://alcatraz.net.in.tum.de/ipv6-hitlist-service/open/aliased-prefixes.txt.xz -o $SCRIPTPATH/data/aliased-prefixes.txt.xz
xz -d $SCRIPTPATH/data/aliased-prefixes.txt.xz
# Shuffle the prefixes, take a fraction of them, and create a prowl compatible targets.csv file
shuf $SCRIPTPATH/data/aliased-prefixes.txt | head -n 10000 | sed 's/$/,ICMPv6,3,32,3/' > $SCRIPTPATH/data/targets.csv

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
    client --config /config/config.yml --probes-file=/data/probes.csv vltatl01,vltcdg01
