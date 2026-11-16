# ClickHouse Tables

This directory contains the ClickHouse table definitions for the nxthdr data pipeline. Each folder corresponds to a database.

## Databases

### BMP Database (`bmp/`)
**Purpose**: Store BMP (BGP Monitoring Protocol) messages collected by Risotto

**Data Source**: Risotto service collecting BMP messages from BIRD routers. Risotto is stateless: it forwards every BMP message type, and routing state is reconstructed in ClickHouse

**Pipeline**: BIRD routers → Risotto → Redpanda (Kafka topic: `risotto`) → ClickHouse

**Schema**: [`message.capnp:Message`](https://github.com/nxthdr/risotto/blob/main/risotto/schemas/message.capnp), to copy into the ClickHouse `format_schemas` directory (`/home/nxthdr/clickhouse/data/format_schemas` on coreams01)

**Tables**:
- `from_kafka` - Kafka engine table consuming Cap'n Proto messages (all BMP message types)
- `updates` - Route Monitoring, one row per prefix update; `initial_dump` flags the table dump following a Peer Up
- `peer_events` - Peer Up and Peer Down
- `sessions` - Initiation and Termination (`synthetic` when the session ended without a Termination: `connection closed` or `collector shutdown`), and `collector_start` (Risotto started: earlier sessions are over)
- `end_of_ribs` - End-of-RIB markers: the table dump of a peer's RIB view and address family is complete
- `stats` - Statistics Reports, one row per counter
- `*_mv` - Materialized views dispatching `from_kafka` rows by message type

**Data Retention**: 7 days TTL for every table

**Migration from the stateful Risotto**: run `migrate-stateless-risotto.sql` before `bmp.sql`

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
