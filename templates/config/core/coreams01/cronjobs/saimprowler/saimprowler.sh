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

# Download the aliased prefixes file with retry logic and error handling
if ! curl -f -s --retry 3 --retry-delay 5 https://alcatraz.net.in.tum.de/ipv6-hitlist-service/open/aliased-prefixes.txt.xz -o $SCRIPTPATH/data/aliased-prefixes.txt.xz; then
    echo "ERROR: Failed to download aliased-prefixes.txt.xz after retries"
    exit 1
fi

# Verify the file was downloaded and is not empty
if [ ! -s $SCRIPTPATH/data/aliased-prefixes.txt.xz ]; then
    echo "ERROR: Downloaded file is empty or does not exist"
    exit 1
fi

# Decompress the file
if ! xz -d $SCRIPTPATH/data/aliased-prefixes.txt.xz; then
    echo "ERROR: Failed to decompress aliased-prefixes.txt.xz"
    exit 1
fi
# Shuffle the prefixes, take a fraction of them, and create a prowl compatible targets.csv file
# Note: shuf may output "Broken pipe" to stderr when head closes early - this is expected behavior
shuf $SCRIPTPATH/data/aliased-prefixes.txt 2>/dev/null | head -n 10000 | sed 's/$/,ICMPv6,3,32,3/' > $SCRIPTPATH/data/targets.csv

# Log the number of targets generated
TARGETS_COUNT=$(wc -l < $SCRIPTPATH/data/targets.csv)
echo "Generated $TARGETS_COUNT targets for measurement"

# Probes generation
docker run --rm --name cron-saimprowler-prowl \
    -v $SCRIPTPATH/data/targets.csv:/data/targets.csv \
    $DOCKER_IMAGE_PROWL \
    --tool traceroute --mapper sequential \
    /data/targets.csv > $SCRIPTPATH/data/probes.csv

# Log the number of probes generated
PROBES_COUNT=$(wc -l < $SCRIPTPATH/data/probes.csv)
echo "Generated $PROBES_COUNT probes from $TARGETS_COUNT targets"

# Probes execution
docker run --rm --name cron-saimprowler-saimiris --network=host \
    -v $SCRIPTPATH/config/config.yml:/config/config.yml \
    -v $SCRIPTPATH/data/probes.csv:/data/probes.csv \
    $DOCKER_IMAGE_SAIMIRIS \
    client --config /config/config.yml --probes-file=/data/probes.csv vltatl01:[2a0e:97c0:8a0::10],vltcdg01:[2a0e:97c0:8a0::10],vltfra01:[2a0e:97c0:8a0::10]
