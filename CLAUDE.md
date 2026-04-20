# Infrastructure Repository Guide for Claude

This document provides context for AI assistants working with the nxthdr infrastructure repository.

## Repository Overview

This repository manages infrastructure for [nxthdr](https://nxthdr.dev) using:
- **Ansible** for configuration management and file synchronization
- **Terraform** for Docker container orchestration
- **Jinja2** templates for dynamic configuration rendering
- **Ansible Vault** for secrets management

## Data Pipeline Architecture

The infrastructure supports three main data pipelines:

### 1. BGP Monitoring (BMP)
- **Service**: Risotto (BMP collector)
- **Database**: `bmp` in ClickHouse
- **Data Flow**: BIRD routers → Risotto → Redpanda (Kafka) → ClickHouse
- **Schema**: Cap'n Proto format (`update.capnp:Update`)
- **Purpose**: Collect and store BGP routing updates from peering sessions

### 2. Flow Monitoring (sFlow)
- **Service**: Pesto (sFlow collector)
- **Database**: `flows` in ClickHouse
- **Data Flow**: Network devices → Pesto → Redpanda (Kafka) → ClickHouse
- **Schema**: Cap'n Proto format (`sflow:SFlowFlowRecord`)
- **Purpose**: Collect and analyze network flow data (IPv6 only)
- **Note**: Only flow samples are processed (counter samples filtered out)

### 3. Active Measurements
- **Service**: Saimiris (probing agent)
- **Database**: `saimiris` in ClickHouse
- **Data Flow**: Saimiris agents → Redpanda (Kafka) → ClickHouse
- **Schema**: Cap'n Proto format (`reply.capnp:Reply`)
- **Purpose**: Active network measurements (traceroute, ping, etc.)

## Server Inventory

The infrastructure consists of four server groups defined in `inventory/inventory.yml`:

### Core Servers
- `coreams01` - Main server (Scaleway, Amsterdam)
- Runs all core services: Grafana, Prometheus, ClickHouse, PostgreSQL, Redpanda, Headscale, etc.

### IXP Servers
- `ixpams01` - iFog, Amsterdam (NL-IX)
- `ixpams02` - iFog, Amsterdam
- `ixpfra01` - iFog, Frankfurt (LocIX, FogIXP)
- `ixpcdg01` - FranceIX, Paris
- `ixpcdg02` - FranceIX, Paris

Run monitoring and BGP routing

### VLT (Probing) Servers

Vultr instances running Saimiris probing infrastructure. The set of active VLT servers changes frequently — `inventory/inventory.yml` is the source of truth.

### Special Groups
- `ixp` and `vlt` groups use shared templates (same config for all hosts in group)
- `core` group uses host-specific templates

### SSH Access

All servers are accessible via SSH as the `nxthdr` user. The FQDNs follow the pattern `{location}.{group}.infra.nxthdr.dev`.

| Host | SSH Command |
|------|-------------|
| coreams01 | `ssh nxthdr@ams01.core.infra.nxthdr.dev` |
| ixpams01 | `ssh nxthdr@ams01.ixp.infra.nxthdr.dev` |
| ixpams02 | `ssh nxthdr@ams02.ixp.infra.nxthdr.dev` |
| ixpfra01 | `ssh nxthdr@fra01.ixp.infra.nxthdr.dev` |
| ixpcdg01 | `ssh nxthdr@cdg01.ixp.infra.nxthdr.dev` |
| ixpcdg02 | `ssh nxthdr@cdg02.ixp.infra.nxthdr.dev` |

VLT servers change frequently. See `inventory/inventory.yml` for current hosts and their `ansible_host` values. The pattern is `{region}{index}.vlt.infra.nxthdr.dev`.

## Main Workflow: `make apply`

The primary deployment command is `make apply`, which executes three sequential steps:

### 1. Render Configuration (`make render`)
Runs two Python scripts using `uv`:
- `render/render_config.py` - Renders Docker container configurations from Jinja2 templates
- `render/render_terraform.py` - Renders Terraform wiring from inventory and secrets

**Process:**
- Reads `inventory/inventory.yml` for server definitions
- Decrypts `secrets/secrets.yml` using vault password from `.password` file
- Renders Jinja2 templates from `templates/config/` → `.rendered/` directory
- Generates Terraform wiring files from inventory:
  - `terraform/docker-providers.tf` (docker provider blocks per host)
  - `terraform/ixp.tf` (IXP module calls)
  - `terraform/vlt.tf` (VLT module calls + vlt_servers locals)
- Renders `templates/terraform/terraform.tfvars.j2` → `terraform/terraform.tfvars`
- `.rendered/` and `terraform/terraform.tfvars` contain plaintext secrets (gitignored)

**Inventory as source of truth:** adding or removing an IXP/VLT server only requires editing `inventory/inventory.yml`. The wiring files are regenerated automatically by `make render-terraform`.

**Template Structure:**
- `templates/config/core/coreams01/` - Host-specific configs for core server
- `templates/config/ixp/` - Shared configs for all IXP servers
- `templates/config/vlt/` - Shared configs for all VLT servers
- `templates/config/shared/` - Common configs across all servers

### 2. Sync Configuration (`make sync-config`)
Runs Ansible playbook: `playbooks/sync-config.yml`
- Uses `ansible.posix.synchronize` (rsync) to copy `.rendered/{hostname}/` → `/home/nxthdr/` on remote servers
- Targets: core, ixp, vlt groups
- No sudo required (runs as `nxthdr` user)

### 3. Apply Terraform (`terraform apply`)
- Executes `terraform -chdir=./terraform apply -auto-approve`
- Creates/updates Docker networks and containers
- Uses Docker provider to connect to remote servers

## Network Configuration Management

### BIRD (BGP Routing)
**Command:** `make sync-bird`

**Process:**
- Runs `playbooks/sync-bird.yml` with sudo (requires BECOME password)
- For **IXP servers**: copies static configs from `networks/{hostname}/bird/` → `/etc/bird/`
- For **VLT servers**: copies rendered configs from `.rendered/{hostname}/bird/` → `/etc/bird/`
- Reloads BIRD service on: ixp and vlt servers
- IXP configs are static files in `networks/`; VLT configs are Jinja2 templates rendered from `templates/config/vlt/bird/`

**Files:**
- `networks/{hostname}/bird/bird.conf` - Main BIRD configuration
- `networks/{hostname}/bird/peerlab.conf` - Optional peerlab config
- `templates/config/shared/bird/bird.service` - Systemd service file

### WireGuard (VPN)
**Command:** `make sync-wireguard`

**Process:**
- Runs `playbooks/sync-wireguard.yml` with sudo (requires BECOME password)
- Templates configs from `networks/{hostname}/wireguard/` → `/etc/wireguard/`
- Restarts `wg-quick@wg0` and `wg-quick@wg1` services
- Targets: core, ixp groups

## Certificate Management

**Process:**
- `proxy` (IPv6) container generates Let's Encrypt certificates via Caddy
- Certificates are automatically available to both proxy containers

**Workflow for new proxied services:**
1. Update proxy configuration in templates
2. Run `make apply` - deploys config and generates certificates automatically

## Secrets Management

**Vault File:** `secrets/secrets.yml` (encrypted with Ansible Vault)

**Commands:**
- `make edit-secrets` - Edit encrypted secrets file (interactive, for humans)
- Requires `.password` file in repo root (gitignored)

**Setup:**
```bash
echo "<VAULT_PASSWORD>" > .password
```

**Editing secrets programmatically (for Claude / CI):**

Since `make edit-secrets` opens an interactive editor, use this 3-step process instead:

1. **Decrypt** to a temporary file:
   ```bash
   ansible-vault decrypt --vault-password-file .password secrets/secrets.yml --output /tmp/secrets_plain.yml
   ```

2. **Edit** the plaintext file at `/tmp/secrets_plain.yml` using the Edit tool.

3. **Re-encrypt** and clean up:
   ```bash
   ansible-vault encrypt --vault-password-file .password /tmp/secrets_plain.yml --output secrets/secrets.yml
   rm -f /tmp/secrets_plain.yml
   ```

Always delete the plaintext file immediately after re-encrypting.

## Common Tasks

### Update Container Configuration
1. Edit template in `templates/config/{group}/{hostname}/{service}/`
2. Run `make apply`
3. If Terraform didn't change, manually restart: `docker restart <container>`

**Config-only changes (no Terraform):** If you only changed config templates (not `coreams01.tf`), you can skip the full `make apply` and instead:
1. `make sync-config` — renders templates and rsyncs to servers
2. `ssh nxthdr@ams01.core.infra.nxthdr.dev "docker restart <container>"` — restart the affected container

This is faster than a full `make apply` when no Terraform resources changed.

### Update Container Image Version
1. For core: edit `terraform/coreams01.tf` directly
2. For IXP: edit `terraform/modules/ixp/main.tf` (applies to all IXP servers)
3. For VLT: edit `terraform/modules/vlt-containers/main.tf` (applies to all VLT servers)
4. Run `make apply`

Renovate can update image versions directly in the module files.

### Update BIRD Configuration
1. Edit `networks/{hostname}/bird/bird.conf`
2. Run `make sync-bird` (requires sudo password)

### Update WireGuard Configuration
1. Edit `networks/{hostname}/wireguard/*.conf`
2. Run `make sync-wireguard` (requires sudo password)

### Add New Service to Core Server
1. Create config directory: `templates/config/core/coreams01/{service}/`
2. Add Jinja2 templates (`.j2` extension) or static files
3. Add Terraform resources in `terraform/coreams01.tf`:
   - `docker_image` resource
   - `docker_container` resource
   - Network attachments, volumes, environment variables
4. Run `make apply`

### Add New IXP Server
1. Add host to `inventory/inventory.yml` under the `ixp` group
2. Add network configs in `networks/{hostname}/`
3. Run `terraform -chdir=./terraform init` then `make apply`

The provider block, module call, and config rendering are all generated automatically from inventory.

### Add New VLT Server

**Recommended: single command**
```
make render-terraform && terraform -chdir=./terraform init && make vlt
```
`make vlt` runs the full sequence: `render-terraform` → `vlt-infrastructure` → `vlt-setup` → `vlt-config`.

**Step-by-step (if resuming a failed run):**
1. Add host to `inventory/inventory.yml` under the `vlt` group (include `uniprobe0` and `ansible_host`)
   - Hostname format: `vlt{region}{index}` where `region` is a 3-char Vultr region code (e.g., `sgp`, `atl`, `cdg`)
   - `uniprobe0`: assign the next available `/48` from `2a0e:97c0:8a0::/44` space
   - `ansible_host`: `{region}{index}.vlt.infra.nxthdr.dev`
2. Run `make render-terraform` to regenerate `vlt.tf`, `docker-providers.tf`, and `terraform.tfvars`
3. Run `terraform -chdir=./terraform init` (to pick up new provider aliases)
4. Run `make vlt-infrastructure` — provisions the Vultr server and DNS. **Must complete before the next step** so Terraform state has the server's IPs (required to render the BIRD config).
5. Run `make vlt-setup` — installs OS packages, Docker, BIRD binary, network config. Note: `vlt-setup` requires the initial root SSH password from the Vultr console for servers where SSH key injection did not succeed. **`vlt-setup` does NOT start BIRD** — the binary is installed but the service file and config are not deployed yet.
6. Run `make vlt-config` — deploys rendered BIRD config + systemd service, **starts BIRD**, then runs `make apply` to deploy Saimiris/Alloy containers.

**Important:** VLT server configs (BIRD, Saimiris, Alloy) are all **template-based** from `templates/config/vlt/` — there is no static `networks/{hostname}/` directory needed for VLT servers (unlike IXP servers). The BIRD config is rendered with the server's actual IPv6 address from Terraform output. `render_config.py` will exit with an error if a VLT host in inventory is missing from Terraform state — this means `vlt-infrastructure` must run before `vlt-setup`/`vlt-config`.

The provider block, module call, VLT server entry, and config rendering are all generated automatically from inventory.

### Remove VLT Server(s)

1. Remove the host entry (or entries) from `inventory/inventory.yml`.
2. Run `make vlt-prune`. It will automatically:
   - Compare inventory with Terraform state to find removed servers
   - Show the list and ask for confirmation
   - Remove Docker container resources from Terraform state (containers are destroyed with the VM)
   - Re-render Terraform files and re-initialize providers
   - Destroy the Vultr VMs and DNS records via `terraform apply`

## ClickHouse Databases

The infrastructure uses ClickHouse for storing time-series data. Database schemas are defined in `clickhouse-tables/`:

### BMP Database (`bmp`)
**Purpose**: Store BGP routing updates from BMP (BGP Monitoring Protocol)

**Tables**:
- `from_kafka` - Kafka engine table consuming from `risotto-updates` topic
- `updates` - MergeTree table storing processed BGP updates
- `from_kafka_mv` - Materialized view transforming Kafka data

**Key Fields**: router address, peer address, prefix, AS path, BGP attributes, timestamps

**TTL**: 7 days

### Flows Database (`flows`)
**Purpose**: Store network flow data from sFlow collectors

**Tables**:
- `from_kafka` - Kafka engine table consuming from `pesto-sflow` topic
- `records` - MergeTree table storing flow records
- `from_kafka_mv` - Materialized view transforming Kafka data

**Key Fields**: source/destination IPs, ports, protocol, packet length, sampling rate

**TTL**: 7 days

**Note**: Only IPv6 flow samples are processed (counter samples filtered at producer)

### ClickHouse Geoip / ASN Lookups

IPInfo dictionaries are available for mapping IP addresses to country and ASN. The lookup requires two steps because IPInfo uses a pointer table:

```sql
-- Step 1: look up the pointer for an address
-- Step 2: use the pointer to look up country/ASN string fields

SELECT
    reply_src_addr,
    dictGetString('ipinfo.country_asn_val', 'asn',
        dictGetUInt64('ipinfo.country_asn_net', 'pointer',
            tuple(toIPv6(reply_src_addr)))) AS asn,
    dictGetString('ipinfo.country_asn_val', 'as_name',
        dictGetUInt64('ipinfo.country_asn_net', 'pointer',
            tuple(toIPv6(reply_src_addr)))) AS as_name,
    dictGetString('ipinfo.country_asn_val', 'country',
        dictGetUInt64('ipinfo.country_asn_net', 'pointer',
            tuple(toIPv6(reply_src_addr)))) AS country,
    count() AS replies
FROM saimiris.replies
WHERE probe_src_addr IN ('2a0e:97c0:8a4:42:0:0:1:0')
GROUP BY reply_src_addr, asn, as_name, country
ORDER BY replies DESC
```

Available string fields in `ipinfo.country_asn_val`: `asn`, `as_name`, `country`, `country_name`.

### Saimiris Database (`saimiris`)
**Purpose**: Store active measurement results from probing agents

**Tables**:
- `from_kafka` - Kafka engine table consuming from `saimiris-replies` topic
- `replies` - MergeTree table storing probe replies
- `from_kafka_mv` - Materialized view transforming Kafka data

**Key Fields**: agent ID, probe/reply addresses, TTL, ICMP type/code, MPLS labels, RTT (`UInt16`, in **tenths of milliseconds** — divide by 10 to get ms, e.g. `rtt / 10.0 AS rtt_ms`)

**TTL**: 7 days

## Directory Structure

```
infrastructure/
├── .password              # Vault password (gitignored)
├── .rendered/             # Rendered configs with secrets (gitignored)
├── Makefile               # Main automation commands
├── inventory/
│   └── inventory.yml      # Server inventory and variables
├── secrets/
│   └── secrets.yml        # Encrypted secrets (Ansible Vault)
├── render/                # Python rendering scripts
│   ├── render_config.py   # Renders Docker configs
│   └── render_terraform.py # Renders Terraform files
├── clickhouse-tables/     # ClickHouse database schemas
│   ├── bmp/               # BGP monitoring database
│   ├── flows/             # Flow monitoring database
│   └── saimiris/          # Active measurements database
├── templates/
│   ├── config/            # Jinja2 templates for configs
│   │   ├── core/          # Core server configs
│   │   ├── ixp/           # Shared IXP configs
│   │   ├── vlt/           # Shared VLT configs
│   │   └── shared/        # Common configs
│   └── terraform/         # Jinja2 template for tfvars
│       └── terraform.tfvars.j2
├── terraform/             # Terraform configuration
│   ├── coreams01.tf       # Core server resources (static)
│   ├── providers.tf       # Provider requirements and non-docker providers (static)
│   ├── docker-providers.tf # Docker provider blocks (generated from inventory)
│   ├── ixp.tf             # IXP module calls (generated from inventory)
│   ├── vlt.tf             # VLT module calls + locals (generated from inventory)
│   ├── vlt-infrastructure.tf # Vultr servers and DNS for VLT (static)
│   ├── terraform.tfvars   # Rendered from secrets (gitignored)
│   └── modules/
│       ├── ixp/           # Shared IXP container definitions
│       ├── vlt-containers/ # Shared VLT container definitions
│       └── vlt-server/    # Vultr server provisioning
├── networks/              # Network configurations (BIRD, WireGuard)
│   ├── coreams01/
│   │   ├── bird/
│   │   └── wireguard/
│   ├── ixpams01/
│   └── ...
├── playbooks/             # Ansible playbooks
│   ├── sync-config.yml    # Sync Docker configs
│   ├── sync-bird.yml      # Sync BIRD configs
│   ├── sync-wireguard.yml # Sync WireGuard configs
│   └── install-*.yml      # Provisioning playbooks
└── docs/
    └── README.md          # Detailed documentation
```

## Important Notes

### File Rendering Rules
- Files with `.j2` extension are rendered as Jinja2 templates
- Shell scripts (`.sh`) automatically get executable permissions
- Non-template files are copied as-is

### Template Context Variables
Available in Jinja2 templates:
- `inventory_hostname` - Current host name (e.g., `coreams01`)
- Group vars from `inventory.yml`
- Host-specific vars from `inventory.yml`
- All secrets from `secrets/secrets.yml`

### Terraform State

- `terraform.tfstate` is git ignored (not committed)
- State managed locally on deployment machine

### Manual Configuration
Some tasks require manual intervention:
- **Grafana admin password:** `docker exec -ti grafana grafana cli admin reset-admin-password <PASSWORD>`
- **Docker firewall rules:** `ip6tables -I DOCKER-USER -d 2a06:de00:50:cafe:100::/80 -j ACCEPT`

### Alerting Pipeline

Alerts flow through: **Prometheus → Alertmanager → Hookshot webhook → Matrix room**

- **Prometheus** scrapes all services and evaluates alert rules from `templates/config/core/coreams01/prometheus/config/alerts.yml`
- **Alertmanager** receives firing/resolved alerts and forwards them to the Hookshot generic webhook
- **Hookshot** bridges the webhook payload into the Matrix alert room (`!YVTFkTAELHJcMYskMC:nxthdr.dev`)
- **Hookshot webhook URL** is stored in `secrets.yml` under `alertmanager.hookshot_webhook_url`

#### Hookshot Webhook Transformation

Hookshot uses a JavaScript transformation function to format alerts with icons and markdown instead of showing raw JSON. This transformation is stored in the **Matrix room state event** `uk.half-shot.matrix-hookshot.generic.hook` (state_key: `alertmanager`) under the `transformationFunction` field.

**Important:**
- The transformation is **not** stored in any config file — it lives only in Matrix room state (persisted in Synapse's database)
- It survives Hookshot restarts and container rebuilds
- It does **not** survive if the webhook is deleted and recreated (e.g., via `!hookshot webhook alertmanager`)
- There is **no bot command** to set transformations. `!hookshot webhook set-transformation` does not exist — it will be misinterpreted as creating a new webhook named "set-transformation"

**To modify the transformation**, edit the room state event via the Matrix client-server API:

1. Create a temporary admin user via MAS (post-MSC3861 migration):
   ```bash
   ssh nxthdr@ams01.core.infra.nxthdr.dev
   # Register a temporary user, then issue an access token with Synapse admin rights
   docker exec -ti mas mas-cli manage register-user \
     --yes -p 'TmpPass123!' -e admin_tmp@nxthdr.dev admin_tmp
   docker exec -ti mas mas-cli manage issue-compatibility-token \
     --yes-i-want-to-grant-synapse-admin-privileges admin_tmp ADMINTMP01
   # Save the printed access_token
   ```
   Note: the legacy `/_synapse/admin/v1/register` endpoint no longer works —
   Synapse delegates auth to MAS, so `registration_shared_secret` is inert.

2. Join the room and get admin power level:
   ```bash
   TOKEN="<access_token>"
   ROOM_ID="%21YVTFkTAELHJcMYskMC%3Anxthdr.dev"
   curl -s "http://[2a06:de00:50:cafe:10::1008]:8008/_synapse/admin/v1/join/$ROOM_ID" \
     -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
     -d '{"user_id":"@admin_tmp:nxthdr.dev"}'
   curl -s "http://[2a06:de00:50:cafe:10::1008]:8008/_synapse/admin/v1/rooms/$ROOM_ID/make_room_admin" \
     -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
     -d '{"user_id":"@admin_tmp:nxthdr.dev"}'
   ```

3. PUT the updated state event (the JS function receives `data` as already-parsed JSON, set `result` as the output):
   ```bash
   curl -s "http://[2a06:de00:50:cafe:10::1008]:8008/_matrix/client/v3/rooms/$ROOM_ID/state/uk.half-shot.matrix-hookshot.generic.hook/alertmanager" \
     -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
     -d '{"name":"alertmanager","transformationFunction":"<your JS code as a single-line string>"}'
   ```

4. Restart Hookshot and deactivate the temp user:
   ```bash
   docker restart hookshot
   curl -s "http://[2a06:de00:50:cafe:10::1008]:8008/_synapse/admin/v1/deactivate/@admin_tmp:nxthdr.dev" \
     -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
     -d '{"erase": true}'
   ```

**Current transformation** formats alerts as:
- 🔴 **FIRING** | AlertName (job) on instance — for critical firing alerts
- 🟡 **FIRING** | AlertName (job) on instance — for warning firing alerts
- ✅ **RESOLVED** | AlertName (job) on instance — for resolved alerts

## Matrix Authentication Service (MAS)

Authentication for Synapse is delegated to MAS (MSC3861 native OIDC). MAS runs at `auth.nxthdr.dev` and federates to Auth0 for actual credentials.

**Topology:**
```
Client ──OIDC──► MAS (auth.nxthdr.dev) ──OIDC upstream──► Auth0
                   │
                   └──MSC3861──► Synapse (matrix.nxthdr.dev)
```

**What MAS owns:**
- All user auth (there are no Synapse-local passwords anymore)
- Access token issuance and introspection
- Compatibility `/login`/`/logout` endpoints for legacy clients
- User registration (gated on Auth0 identity)

**What it does *not* touch:**
- Appservices (Hookshot) — they use appservice tokens and bypass MAS entirely
- Room state, messages, federation — all still Synapse

### One-time migration runbook (syn2mas)

Only needed the first time MAS is stood up. Performed 2026-04-20; kept here
for reference and for future deployments.

Two gotchas that bit us:
- The MAS container image is distroless; `syn2mas --synapse-database-uri` with
  an IPv6-in-brackets URL silently falls back to localhost, so pass DB config
  via libpq `PG*` env vars with URI `postgresql:`.
- `syn2mas` needs to see the *old* `oidc_providers:` block to map legacy
  users onto MAS upstream providers. After MSC3861 is merged into
  `homeserver.yaml.j2`, you must reconstruct a temporary homeserver.yaml
  with the pre-migration `oidc_providers:` block for the tool to read. The
  corresponding MAS upstream provider needs a matching `synapse_idp_id:
  "oidc-<idp_id>"` field.

```bash
ssh nxthdr@ams01.core.infra.nxthdr.dev

# 1. Backup Postgres (mandatory — syn2mas is not reversible).
docker exec postgresql pg_dumpall -U postgres | gzip > ~/pgdump-pre-mas-$(date +%F).sql.gz

# 2. Create the MAS database and let MAS boot (migrations run on startup).
docker exec postgresql psql -U postgres -c 'CREATE DATABASE mas;'
docker restart mas

# 3. Upload a reconstructed homeserver.yaml with the pre-migration
#    oidc_providers block into the MAS container at /tmp/homeserver.yaml.

# 4. Check, then migrate.
docker exec \
  -e PGHOST=2a06:de00:50:cafe:10::116 -e PGPORT=5432 \
  -e PGUSER=postgres -e PGPASSWORD=<password> -e PGDATABASE=synapse \
  mas mas-cli syn2mas -c /config/config.yaml \
  --synapse-config /tmp/homeserver.yaml \
  --synapse-database-uri 'postgresql:' check

docker stop synapse
docker exec <same-env> mas mas-cli syn2mas -c /config/config.yaml \
  --synapse-config /tmp/homeserver.yaml \
  --synapse-database-uri 'postgresql:' migrate
docker start synapse
```

### Admin operations

Available `mas-cli manage` subcommands: `register-user`,
`issue-compatibility-token`, `lock-user`, `unlock-user`, `set-password`,
`kill-sessions`, `provision-all-users`. There's no `list-users`; query the
`users` table in the `mas` Postgres DB directly if you need a listing.

The old `registration_shared_secret` flow in Synapse admin API is inert post-migration.

### Rollback

If MAS goes wrong and you need to revert to Auth0-direct:
1. Restore Postgres dump from step 1 above (this rolls back syn2mas data changes).
2. Revert the `experimental_features.msc3861:` block in `homeserver.yaml.j2`; restore the `oidc_providers:` block and `registration_shared_secret:` line from git.
3. `make apply` + `docker restart synapse`.
4. MAS container can keep running or be removed.

## Troubleshooting

### Configuration not applied
- Check if Terraform detected changes: `terraform -chdir=./terraform plan`
- If no changes, manually restart container: `docker restart <container>`

### Secrets decryption fails
- Verify `.password` file exists and contains correct password
- Test with: `make edit-secrets`

### Ansible connection fails
- Verify SSH access: `ssh nxthdr@{hostname}.infra.nxthdr.dev`
- Check inventory file for correct `ansible_host`

### Rendering fails
- Check for undefined variables in templates
- Verify secrets file contains required keys
- Review error output from `render_config.py` or `render_terraform.py`

## Best Practices

1. **Review changes:** Check what will change before applying
2. **Review Terraform plan:** Use `terraform -chdir=./terraform plan` if needed
3. **Backup before major changes:** Terraform state is in git, but configs are not
4. **Use descriptive commit messages:** Infrastructure changes should be well-documented
5. **Test on single host first:** For multi-host changes, test on one server before rolling out
6. **Keep secrets secure:** Never commit `.password` or `.rendered/` directory
7. **Document manual steps:** Update this file when adding new manual configuration requirements

## Quick Reference

| Task | Command | Requires Sudo |
|------|---------|---------------|
| VLT agent status | `make vlt-status` | Yes |
| Full deployment | `make apply` | No |
| Render configs | `make render` | No |
| Sync configs | `make sync-config` | No |
| Update BIRD | `make sync-bird` | Yes |
| Update WireGuard | `make sync-wireguard` | Yes |
| Edit secrets | `make edit-secrets` | No |
| Add VLT server (full) | `make render-terraform && terraform -chdir=./terraform init && make vlt` | Yes (vlt-setup) |
| Remove VLT server(s) | `make vlt-prune` | No |
| Destroy infrastructure | `make destroy` | No |
| Restart container | `docker restart <name>` | On remote host |
