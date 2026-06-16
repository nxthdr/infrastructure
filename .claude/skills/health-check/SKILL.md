---
name: health-check
description: Read-only fleet health sweep for the nxthdr infrastructure. Verifies container status across core/ixp/vlt servers, ClickHouse data pipeline freshness (bmp/flows/saimiris), and BIRD service status. Use when the user asks to check that the infrastructure is working, after a deploy, when investigating an alert, or when wanting a quick "is everything OK?" summary. Always safe — no sudo, no writes.
---

# Health Check

Run a full-fleet, read-only health sweep of the nxthdr infrastructure and report a concise status summary.

## Source of truth

`inventory/inventory.yml` defines the current set of servers. **Servers change over time** — never hard-code hostnames. Always use `ansible` with `-i inventory/inventory.yml` so the inventory is consulted on every run.

Groups: `core`, `ixp`, `vlt`. All hosts run as user `nxthdr` over SSH.

## Checks to run

Run these in parallel (single message, multiple Bash tool calls). All must work without sudo:

### 1. Fleet container status

```bash
ansible -i inventory/inventory.yml all \
  -a 'docker ps -a --format "{% raw %}{{.Names}}\t{{.Status}}{% endraw %}"' \
  --one-line 2>/dev/null
```

The `{% raw %}` wrappers are required because ansible parses `{{.Names}}` as Jinja2 before sending the command to the remote. Without them, ansible errors with `template error while templating string: unexpected '.'`.

Parse the output and flag anything that is:
- `Restarting` — container is crash-looping
- `Exited` with a **recent** timestamp (less than a day) — recently crashed
- Containers expected to be `(healthy)` that aren't (only count those that declare a healthcheck)

**Known-orphan exited containers on `coreams01`** (8-month-old experiments, ignore unless the user asks to clean up): `brave_bohr`, `mystifying_almeida`, `crazy_zhukovsky`, `sad_napier`.

### 2. ClickHouse pipeline freshness

ClickHouse is publicly reachable through chproxy at `https://clickhouse.nxthdr.dev` with the read-only user `read:read` (hardcoded in `templates/config/core/coreams01/chproxy/config/config.yml`, not a secret). Query it directly with `curl` — no SSH hop needed.

**Important:** Two curl patterns work — GET query param or raw POST body. What **doesn't** work is form-encoded POST (`--data-urlencode` without `-G`): chproxy passes the URL-encoded body verbatim to ClickHouse, which then fails on `%3E` (the encoded `>`) with a `SYNTAX_ERROR`.

The three pipelines have different cadences and need different freshness windows:

| Pipeline | Cadence | Stale threshold |
|---|---|---|
| `bmp.updates` | continuous (BGP updates from peers) | no rows in last **5 min** |
| `flows.records` | continuous (sFlow samples) | no rows in last **5 min** |
| `saimiris.replies` | **bursty** — driven by `saimprowler.timer` every 30 min | no rows in last **1 hour** |

The saimiris pipeline only flows when `saimprowler` dispatches a probe batch from `coreams01` (timer fires every 30 min, batch takes a few minutes). Between bursts, `saimiris.replies` is empty — that is **expected**, not a stall. Use a 1-hour window to detect real outages.

```bash
curl -s -G 'https://clickhouse.nxthdr.dev/?user=read&password=read' \
  --data-urlencode "query=
    SELECT 'bmp.updates' AS pipeline, count() AS rows, max(time_received_ns) AS latest
    FROM bmp.updates WHERE time_received_ns > now() - INTERVAL 5 MINUTE
    UNION ALL
    SELECT 'flows.records', count(), max(time_received_ns)
    FROM flows.records WHERE time_received_ns > now() - INTERVAL 5 MINUTE
    UNION ALL
    SELECT 'saimiris.replies (1h)', count(), max(time_received_ns)
    FROM saimiris.replies WHERE time_received_ns > now() - INTERVAL 1 HOUR
    FORMAT PrettyCompact"
```

If `saimiris.replies` is empty in the 1-hour query, also check the timer status before declaring a problem:

```bash
ssh nxthdr@$(ansible-inventory -i inventory/inventory.yml --host coreams01 \
  | jq -r '.ansible_host') 'systemctl list-timers saimprowler --all'
```

A healthy timer shows a `LAST` time within the last 30 minutes and a `NEXT` time within the next 30. If the last run is much older, that's the actual problem — investigate `journalctl -u saimprowler` on the core host.

A `1970-01-01` `latest` value means no rows matched the time filter (i.e. the pipeline has been stalled for at least the window size).

### 3. BIRD service status (ixp + vlt)

```bash
ansible -i inventory/inventory.yml 'ixp:vlt' \
  -a 'systemctl is-active bird' --one-line 2>/dev/null
```

Flag any host where the service is not `active`. For deeper BIRD diagnostics (peer state, route counts) the user can run `make vlt-status` — that uses sudo and shows `birdc show protocols`. Don't run it automatically (it prompts for a password).

### 4. Disk and load (optional, only if other checks pass)

If everything else is green, a quick sanity sweep is useful:

```bash
ansible -i inventory/inventory.yml all \
  -a 'sh -c "df -h / | tail -1; uptime"' --one-line 2>/dev/null
```

Flag `/` over 85% or load average above number of cores.

## Reporting

Be concise. Default output is a small table:

```
Fleet: 9 hosts, N containers running, 0 restarting, 0 unexpected exits
Pipelines (last 5m):
  bmp.updates       2,400  fresh (last: 10:37:44)
  flows.records     1,254  fresh (last: 10:37:49)
  saimiris.replies 63,647  fresh (last: 10:37:48)
BIRD: 8/8 active
```

If something is wrong:
- Name the specific host and container/pipeline
- Suggest the next diagnostic step (e.g. `docker logs <name>`, `make vlt-status`, `journalctl -u bird` on the affected host)
- Do **not** attempt to remediate without asking

If a host is unreachable via ansible, report it but continue with the rest.

## What this skill does NOT do

- Does not restart containers, services, or hosts.
- Does not run `make apply` or any deploy step (use `/deploy` for that).
- Does not require sudo. For sudo-required deep checks (`birdc show protocols`, log inspection on restricted paths), point the user at `make vlt-status` or specific manual commands.
