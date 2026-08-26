# Alerting & Silences

Alerts flow **Prometheus → Alertmanager → Hookshot webhook → Matrix** room. This
page covers how to **silence** alerts (suppress notifications) when an issue is
known and being tracked, so the Matrix room stays useful.

## Alertmanager UI

Alertmanager is exposed behind HTTP basic auth at:

- **<https://alertmanager.nxthdr.dev>** — user `admin`, the shared admin password.

It is served by the `proxy` (Caddy) container, which reverse-proxies to the
internal Alertmanager (`[2a06:de00:50:cafe:10::106]:9093`) and enforces
`basic_auth` (see `templates/config/core/coreams01/proxy/config/Caddyfile.j2`).
The credential is `alertmanager.hashed_password` in `secrets/secrets.yml`
(a Caddy/bcrypt hash of the admin password, the same one used for Loki and
Prometheus).

!!! note
    There is a **wildcard `*.nxthdr.dev` DNS record** pointing at the proxy, so
    new subdomains like this one resolve automatically and Caddy issues the TLS
    certificate on first request — no DNS change is needed to add a vhost.

## Creating a silence (UI)

1. Open <https://alertmanager.nxthdr.dev> and log in (`admin` / admin password).
2. Click **Silences → New Silence** (or **Silence** directly on a firing alert,
   which pre-fills the matchers).
3. Set **matchers** — label/value pairs identifying the alerts to suppress.
   Use a regex matcher (toggle the `=~` option) to cover several at once.
4. Set the **duration** (start/end), your **name**, and a **comment** explaining
   *why* (link the ticket). The comment is mandatory and is how the next person
   understands the silence.
5. **Create**. Matching alerts move to `suppressed` and stop notifying. They
   auto-resolve normally when the underlying condition clears, and the silence
   auto-expires at its end time (re-firing then, as a reminder to follow up).

### Useful labels for our alerts

| Alert | Labels to match on |
|-------|--------------------|
| `BGP_Session_Down` | `alertname`, `instance` (e.g. `ixpfra01`), `name` (session, e.g. `HE`, `LocIXRS1`) |
| `Service_Down` / `Service_Disappeared` | `alertname`, `job`, `instance` |
| `Host_Disk_Full` / `Host_Out_Of_Memory` | `alertname`, `instance` |

**Example** — suppress the known LocIX/iFog Frankfurt outage on `ixpfra01`
without hiding other sessions on that host:

| Matcher | Value | Regex |
|---------|-------|-------|
| `alertname` | `BGP_Session_Down` | no |
| `instance` | `ixpfra01` | no |
| `name` | `HE\|Cloudflare\|LocIXRS[0-9]` | yes |

## Creating a silence (API / automation)

The UI is backed by the Alertmanager v2 API, reachable the same way
(`https://alertmanager.nxthdr.dev/api/v2/silences`) or internally from the core
host (`http://[2a06:de00:50:cafe:10::106]:9093/api/v2/silences`, no auth inside
the backend network). Example, run from `coreams01`:

```bash
python3 - <<'PY'
import json, datetime, urllib.request
now = datetime.datetime.now(datetime.timezone.utc)
body = {
    "matchers": [
        {"name": "alertname", "value": "BGP_Session_Down", "isRegex": False, "isEqual": True},
        {"name": "instance",  "value": "ixpfra01",         "isRegex": False, "isEqual": True},
        {"name": "name",      "value": "HE|Cloudflare|LocIXRS[0-9]", "isRegex": True, "isEqual": True},
    ],
    "startsAt": now.isoformat(),
    "endsAt":   (now + datetime.timedelta(days=30)).isoformat(),
    "createdBy": "your-name",
    "comment":  "Known LocIX/iFog FRA outage since 2026-05-11 (ticket #...).",
}
req = urllib.request.Request(
    "http://[2a06:de00:50:cafe:10::106]:9093/api/v2/silences",
    data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
print(urllib.request.urlopen(req).read().decode())
PY
```

List active silences:

```bash
curl -s -u admin:PASSWORD https://alertmanager.nxthdr.dev/api/v2/silences | jq '.[] | {id, state: .status.state, comment}'
```

Expire (delete) a silence early:

```bash
curl -s -u admin:PASSWORD -X DELETE https://alertmanager.nxthdr.dev/api/v2/silence/<silence-id>
```

## Notes

- A silence only suppresses **notifications**; the alert still evaluates and will
  show in the UI. When the condition clears, the alert resolves regardless of the
  silence.
- Keep silences **scoped** (match the specific sessions/instances affected) so a
  *new, unrelated* problem on the same host still pages.
- Always set a meaningful **expiry** and **comment** — an un-expiring, unexplained
  silence is how real outages get missed.

## Silence persistence

Silences live in alertmanager's own state store (`--storage.path=/data`, bind-mounted
from `/home/nxthdr/alertmanager/data` on `coreams01`), **not** in any config file in
this repo. They survive restarts only because that directory is writable by the
container's uid.

That was broken from Nov 2024 until 2026-08-26: the directory was owned by `nxthdr`
(1001) while alertmanager runs as `nobody` (65534), so nothing was ever persisted and
**every restart silently discarded all silences**. It surfaced when a `make apply`
bumped alertmanager to 0.34.0 and the long-standing Frankfurt LocIX silence vanished,
putting five `ixpfra01` BGP alerts back into the room with no explanation.

Before trusting a silence to outlive a deploy, check the state files exist:

```bash
ssh nxthdr@ams01.core.infra.nxthdr.dev 'ls -la /home/nxthdr/alertmanager/data'
# expect: silences  and  nflog, both owned by nobody
```

An **empty** directory means the ownership fix is missing (see CLAUDE.md →
"Manual Configuration"); create silences all you like, none will survive the next
container replacement. The same permission also gates the **notification log**, so
without it alertmanager re-sends alerts it had already delivered after each restart.

Because the store is host state and not in git, a rebuilt core server starts out
broken again — and with no silences to lose, the only visible symptom is a pair of
`permission denied` maintenance errors in `docker logs alertmanager`.
