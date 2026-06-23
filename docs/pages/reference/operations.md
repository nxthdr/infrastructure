# Operations & Tooling

Day-to-day operation of the infrastructure is supported by repository tooling (Claude Code skills) and a public, read-only query endpoint.

## Operator skills (Claude Code)

The repository ships Claude Code skills under `.claude/skills/` that encode the common operational workflows. When working in the repo with Claude Code, invoke them with `/<name>`:

| Skill | What it does | Safety |
|---|---|---|
| `/deploy` | Renders configs, runs `terraform plan`, **pauses for explicit confirmation**, applies, then verifies the fleet. | Never auto-applies |
| `/health-check` | Read-only fleet sweep: container status across core/ixp/vlt, ClickHouse pipeline freshness, BIRD status. | No sudo, no writes |
| `/rollback` | Rolls a service back to a known-good image after a bad update — finds the last-good digest, pins it in Terraform, applies scoped to that service, then verifies. | Plan + confirm before apply |

Each skill's `SKILL.md` holds the full step-by-step procedure.

### Why rollback needs a dedicated procedure

Most first-party services track the floating `ghcr.io/nxthdr/*:main` tag via a `data.docker_registry_image` + `pull_triggers` block, so the running version is **not recorded in git**, and re-running `make apply` simply re-pulls the same (possibly broken) `:main`. Rolling back therefore means repointing at an **immutable** image — a `@sha256:` digest or an immutable tag — and applying **scoped** with `-target` (never `make apply`, which would drag every other `:main` service forward at the same time). The `/rollback` skill walks through finding the last-good digest (host `docker images --digests`, Loki, or GHCR), pinning it, and the un-pin follow-up.

Floating-tag services: `:main` first-party (`risotto`, `pesto`, `saimiris` [all VLT hosts], `saimiris-gateway`, `peerlab-gateway`, `nxthdr.dev`, `blog`, `docs`, `peers`) and `:latest` third-party (`tailscale` [all IXP hosts], `bgpalerter`). Everything else is pinned to an explicit version and rolls back with a plain `git revert` of the version bump.

## Querying the data (chproxy)

ClickHouse is reachable read-only from outside the infrastructure through **chproxy** at `https://clickhouse.nxthdr.dev`, using the hardcoded read-only credentials `read:read` (not a secret). Use this for ad-hoc queries, dashboards, and scripts instead of SSH-ing to the core server.

!!! warning "Send the query as a GET parameter, not a form-encoded POST body"
    chproxy forwards an un-decoded form body verbatim to ClickHouse, so `>` arrives as `%3E` and you get a syntax error. Use `curl -G --data-urlencode` (a raw `--data-binary @-` POST body also works):

    ```bash
    curl -s -G 'https://clickhouse.nxthdr.dev/?user=read&password=read' \
      --data-urlencode 'query=SELECT count() FROM bmp.updates
        WHERE time_received_ns > now() - INTERVAL 5 MINUTE FORMAT PrettyCompact'
    ```

### Pipeline freshness windows

The three data pipelines have different cadences — use the right window when checking freshness:

| Pipeline | Cadence | Stale if no rows in |
|---|---|---|
| `bmp.updates` | continuous (BGP updates from peers) | last 5 min |
| `flows.records` | continuous (sFlow samples) | last 5 min |
| `saimiris.replies` | **bursty** — `saimprowler` dispatches a batch every 30 min | last 1 hour |

A `saimiris.replies` gap inside a 5-minute window is almost always the normal inter-burst lull, not an outage — see the note in [Architecture → Active Measurement Pipeline](architecture.md#active-measurement-pipeline). For the database/table layout, see [Architecture → ClickHouse Database Architecture](architecture.md#clickhouse-database-architecture).
