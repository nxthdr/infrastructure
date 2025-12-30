# ClickHouse Tables

This directory contains the ClickHouse table definitions for the nxthdr data pipeline. Each folder corresponds to a database.

## Databases

### BMP Database (`bmp/`)
**Purpose**: Store BGP routing updates collected via BMP (BGP Monitoring Protocol)

**Data Source**: Risotto service collecting BMP messages from BIRD routers

**Pipeline**: BIRD routers → Risotto → Redpanda (Kafka topic: `risotto-updates`) → ClickHouse

**Tables**:
- `from_kafka` - Kafka engine table consuming Cap'n Proto messages
- `updates` - MergeTree table with processed BGP updates
- `from_kafka_mv` - Materialized view for data transformation

**Data Retention**: 7 days TTL

### Flows Database (`flows/`)
**Purpose**: Store network flow data from sFlow collectors

**Data Source**: Pesto service collecting sFlow datagrams from network devices

**Pipeline**: Network devices → Pesto → Redpanda (Kafka topic: `pesto-sflow`) → ClickHouse

**Tables**:
- `from_kafka` - Kafka engine table consuming Cap'n Proto messages
- `records` - MergeTree table with flow records
- `from_kafka_mv` - Materialized view for data transformation

**Data Retention**: 7 days TTL

**Note**: Only flow samples are processed (IPv6 only). Counter samples are filtered at the producer level.

### Saimiris Database (`saimiris/`)
**Purpose**: Store active measurement results from probing agents

**Data Source**: Saimiris agents performing network measurements

**Pipeline**: Saimiris agents → Redpanda (Kafka topic: `saimiris-replies`) → ClickHouse

**Tables**:
- `from_kafka` - Kafka engine table consuming Cap'n Proto messages
- `replies` - MergeTree table with probe replies
- `from_kafka_mv` - Materialized view for data transformation

**Data Retention**: 7 days TTL

## Creating Databases

Each database should be created with:

```sql
CREATE DATABASE <database_name>;
```

Then run the SQL file in the corresponding folder to create tables:

```bash
clickhouse-client --queries-file=<database_name>/<database_name>.sql
```
