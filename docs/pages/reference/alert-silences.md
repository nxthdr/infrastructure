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

## Currently tracked outages

Two upstream BGP outages are currently silenced, both **provider-side** — no
BIRD or host change will fix either, so re-diagnosing them from scratch each
time they resurface is wasted effort. Note the differing expiries: they encode
how long each is expected to last, so a short one coming back is a signal, not
noise.

| Silence | Scope | Expires | Cause |
|---|---|---|---|
| `154459ab` | `ixpfra01`, `name=~HE\|Cloudflare\|LocIXRS[0-9]` | 2026-09-25 | LocIX/iFog Frankfurt outage (RS2/RS3/Cloudflare down since 2026-05-11, HE/RS1 since 2026-06-12) |
| `88c636ac` | `ixpfra01`, `name=FogIXPRS1` | 2026-09-06 | FogIXP route server RS1 pulled from service 2026-08-30 (**7 days on purpose** — expected back) |

No silence covers `peerlab_*` sessions on those hosts, so participant sessions
still page normally — and none covers `FogIXPRS2`.

The NL-IX silence (`773699ad`) was **expired early on 2026-09-03** when that
outage resolved. Expiring a stale silence is part of closing an incident: left
alone it would have masked real NL-IX and HE failures on both Amsterdam hosts
until 2026-09-26.

### NL-IX VLAN dead at iFog Amsterdam (2026-08-19 → 2026-09-02) — RESOLVED

!!! success "Resolved 2026-09-02 ~22:57"
    iFog fixed the bridge. All eight sessions (v4 + v6 on both hosts) are
    Established and `ixpams01` ↔ `ixpams02` across the bridge pings in 0.35 ms.
    Kept here because the diagnosis method is reusable — the fault was invisible
    from BIRD, and two of the obvious checks actively mislead.

Five sessions — `NLIXRS1v6`, `NLIXRS2v6`, `HE` on `ixpams01` and `NLIXRS1v6`,
`NLIXRS2v6` on `ixpams02` — went to `Connect / Hold timer expired` within 90
seconds of each other at **2026-08-19 18:08 CEST** and stayed there. The
peering interface `ens19` received **zero inbound packets** on both hosts.

Diagnosed provider-side rather than ours:

- Two independent VMs failed simultaneously; a single peer fault cannot do that.
- `ip -6 neigh show dev ens19` is `FAILED`/`INCOMPLETE` for *every* neighbour —
  including `ixpams01` ↔ `ixpams02`, which sit on the same peering LAN.
- `tcpdump -i ens19` captures only our own outbound neighbour solicitations.
- `ens18` (iFog transit) is healthy: gateway replies in 0.2 ms, default route
  works, no carrier/link events in the journal, no repo change to network config.
- FranceIX sessions on `ixpcdg01`/`ixpcdg02` stayed Established, so it is
  neither our ASN nor a global problem.

**Narrowed on 2026-09-02 to iFog's hypervisor bridge, not NL-IX.** Both VMs'
`ens19` hang off the same Proxmox host, which identifies itself in LLDP as
`vmhost06-ams.ifog.ch` (taps `tap756i1` for ams01, `tap768i1` for ams02) and
advertises a management address *inside* the peering LAN,
`2001:7f8:13:0:a21d:48ff:feef:5e0c`. So that bridge really is the NL-IX VLAN
bridge, our vNICs are attached to it, and it is up — its LLDP arrives on both
taps. It nevertheless forwards nothing:

- Neither VM can ping the hypervisor's own peering-LAN address.
- **ams01 and ams02 cannot reach each other**, on IPv6 or IPv4, despite being
  two taps on the same bridge — traffic that never needs to touch NL-IX at all.

That combination (LLDP in, nothing else in, no VM-to-VM forwarding) puts the
fault squarely inside `vmhost06-ams` — port isolation, a broken bridge, or lost
VLAN membership. It is **not** NL-IX, and **not** anything in our BIRD config or
addressing. The fix is an iFog ticket naming that host and those two tap ports.

**Before renewing the silence, re-verify — and mind the two traps:**

```bash
# Trap 1: your OWN outbound ARP/NS shows up in a plain capture and looks like traffic.
# Trap 2: iFog's hypervisor sends LLDP every 30 s, which arrives even while broken.
# So exclude your own MAC, and don't count LLDP as recovery:
MAC=$(cat /sys/class/net/ens19/address)
sudo timeout 25 tcpdump -nni ens19 "not ether src $MAC and not ether proto 0x88cc"

# still broken: 0 packets captured
# recovered:    route-server / participant ND and BGP visible -> debug BIRD instead
```

The fastest single check is VM-to-VM across the bridge, which needs no peer at
all — if this works, the bridge is forwarding again:

```bash
ssh nxthdr@ams01.ixp.infra.nxthdr.dev 'ping6 -c3 2001:7f8:13::a500:9434:1'  # -> ams02
```

!!! warning "Collateral: blackhole routes on the dead LAN"
    Both hosts carry hand-added static routes (`ip -6 route add`, kernel source
    3 = `RTPROT_BOOT`) whose next-hops are on this LAN. Because they are not
    BGP-learned, **BIRD cannot withdraw them** — it imports them via `kernel1` —
    so they blackhole traffic instead of falling back to the iFog default route:

    - `ixpams01`: `2001:4860::/32` via HE, `fd00:babe::/64` via `ixpams02`
    - `ixpams02`: `2001:4860::/32` and `2a07:8880:2::/48` via AS16509

    All Google IPv6 is therefore unreachable from both hosts. Check with
    `ip -6 route show | grep "dev ens19"` and trace an origin with
    `birdc show route for <addr> all`. These belong to the hand-managed
    ixpams01/ixpams02 experiment, so confirm before deleting.

### FogIXP route server RS1 pulled from service (2026-08-30)

`FogIXPRS1` (`2001:7f8:ca:1::111`, AS47498) sent a graceful BGP **Administrative
shutdown** at **15:20:26 UTC** and then left the peering LAN altogether.

Unlike the two outages above, the **LAN is healthy** — this is one route server,
not a dead VLAN, and telling the two apart takes one command:

- `ip -6 neigh show | grep 2001:7f8:ca:1:` lists 20+ neighbours REACHABLE/STALE
  on `ens20`; only `::111` is `FAILED`.
- `FogIXPRS2` (`::222`) stayed Established with ~4698 routes imported, so
  FogIXP reachability continues through the surviving route server.

RS1 was already misbehaving three days earlier, which is likely why it was
pulled:

```
Aug 27 22:16:40  FogIXPRS1: Malformed attribute list - framing error (1024/3) at 75
Aug 27 22:16:40  FogIXPRS1: Invalid route 2001:67c:1550::/48 withdrawn
Aug 30 15:20:26  FogIXPRS1: Received: Administrative shutdown
```

Worth reporting the malformed-attribute event to FogIXP — they may not have it.

!!! tip "Why this silence is 7 days and not 30"
    A route server returning is the *expected* outcome, so the silence is set to
    expire while the situation is still fresh. If `FogIXPRS1` pages again on
    2026-09-06 that is useful information — either it is still out (chase FogIXP)
    or it came back and broke again. A 30-day silence would have turned that
    signal into a month of silence. Match the expiry to the expected fix time,
    not to habit.

    Route servers are a redundant pair: losing one is a *degradation*, not an
    outage. If **both** FogIXP sessions go down, that is a different incident —
    check the LAN with `tcpdump -nni ens20` before assuming it is IXP-side.

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
