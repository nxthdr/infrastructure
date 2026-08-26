#!/usr/bin/env python3
"""Triage nxthdr Alertmanager alerts for an AI agent.

Reads the Alertmanager v2 API `/api/v2/alerts` JSON on **stdin** and prints a
concise, agent-friendly triage: what needs attention now, what is known-noise
that should be silenced, and what is already silenced/inhibited. Stdlib only.

Fetch + pipe (no auth, no hardcoded IP — discovers the container address):

  ssh nxthdr@ams01.core.infra.nxthdr.dev \
    'IP=$(docker inspect -f "{{range .NetworkSettings.Networks}}{{.GlobalIPv6Address}}{{end}}" alertmanager); \
     curl -s "http://[$IP]:9093/api/v2/alerts"' \
    | python3 triage.py

Exit code is 0 normally, 2 if there is at least one NEEDS-ATTENTION alert
(unsilenced and not known-noise) — handy for scripts.
"""
import sys
import json
import re
from datetime import datetime, timezone

# --- Known non-actionable recurring alerts -------------------------------
# Keep in sync with docs/pages/reference/alert-silences.md and the
# `project_recurring_alerts` memory. An alert is "known noise" when every
# key in `match` equals its label AND every *_regex (if present) matches.
KNOWN_NOISE = [
    {
        "id": "fra-locix",
        "match": {"alertname": "BGP_Session_Down", "instance": "ixpfra01"},
        "regex": {"name": r"^(HE|Cloudflare|LocIXRS[0-9])$"},
        "note": ("Known LocIX/iFog Frankfurt outage (upstream/IXP-side, sessions stuck in Connect). "
                 "Silence it — matcher in docs/pages/reference/alert-silences.md."),
    },
]

# --- Diagnostic hints for alerts that ARE actionable ---------------------
# Same matching shape as KNOWN_NOISE, but these do *not* suppress an alert —
# they attach a "start here" line to it. `Host_Out_Of_Memory` @ vlt* used to be
# listed as benign noise above, and that verdict is exactly why a real outage
# hid behind it for weeks (2026-08-25): saimiris was leaking AF_PACKET ring
# buffers and sending no probes at all.
HINTS = [
    {
        "id": "vlt-oom",
        "match": {"alertname": "Host_Out_Of_Memory"},
        "regex": {"instance": r"^vlt"},
        "note": ("Actionable — do NOT dismiss as a flap. Almost certainly saimiris leaking pcap "
                 "ring buffers because CaracatSender::new() hangs on NDP resolution: check "
                 "`sudo grep -c socket: /proc/$(pgrep -o saimiris)/maps` (healthy = 1-2, leaking = dozens) "
                 "and `docker logs saimiris | grep 'Failed to create Caracat sender'`. Root cause is a "
                 "second global IPv6 address on enp1s0 (dhcpcd `slaac private`); the agent sends zero "
                 "probes while it leaks. See project_recurring_alerts memory + nxthdr/saimiris#66."),
    },
]

SEV_ORDER = {"critical": 0, "error": 1, "warning": 2, "info": 3}
NOW = datetime.now(timezone.utc)


def match_entry(labels, entries):
    for entry in entries:
        if any(labels.get(k) != v for k, v in entry["match"].items()):
            continue
        if any(not re.search(rx, labels.get(k, "")) for k, rx in entry.get("regex", {}).items()):
            continue
        return entry
    return None


def match_noise(labels):
    return match_entry(labels, KNOWN_NOISE)


def match_hint(labels):
    return match_entry(labels, HINTS)


def age(ts):
    try:
        t = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return "?"
    d = NOW - t
    days, rem = d.days, d.seconds
    h, m = rem // 3600, (rem % 3600) // 60
    if days > 0:
        return f"{days}d{h}h"
    if h > 0:
        return f"{h}h{m}m"
    return f"{m}m"


def sev(a):
    return a["labels"].get("severity", "warning")


def line(a):
    l = a["labels"]
    ann = a.get("annotations", {})
    title = ann.get("title") or ann.get("summary") or ann.get("description", "")
    extra = []
    if l.get("name"):
        extra.append(f"session={l['name']}")
    if l.get("state"):
        extra.append(f"state={l['state'].strip()}")
    head = f"  [{sev(a).upper()}] {l.get('alertname')} @ {l.get('instance','?')}  (firing {age(a['startsAt'])})"
    out = [head, f"      {title}"]
    if extra:
        out.append("      " + "  ".join(extra))
    return "\n".join(out)


def main():
    raw = sys.stdin.read().strip()
    if not raw:
        print("No input on stdin. Pipe the /api/v2/alerts JSON in.", file=sys.stderr)
        return 1
    alerts = json.loads(raw)

    needs, noise_firing, silenced, inhibited = [], [], [], []
    for a in alerts:
        st = a.get("status", {})
        if st.get("silencedBy"):
            silenced.append(a)
        elif st.get("inhibitedBy"):
            inhibited.append(a)
        elif match_noise(a["labels"]):
            noise_firing.append(a)
        else:
            needs.append(a)

    for bucket in (needs, noise_firing, silenced, inhibited):
        bucket.sort(key=lambda a: (SEV_ORDER.get(sev(a), 9), a["labels"].get("instance", "")))

    print(f"Alertmanager: {len(alerts)} alert(s) — "
          f"{len(needs)} NEEDS ATTENTION, {len(noise_firing)} known-noise firing, "
          f"{len(silenced)} silenced, {len(inhibited)} inhibited\n")

    if needs:
        print("🔴 NEEDS ATTENTION (unsilenced, not known-noise):")
        hinted = set()
        for a in needs:
            print(line(a))
            hint = match_hint(a["labels"])
            if hint and hint["id"] not in hinted:
                print(f"      → {hint['note']}")
                hinted.add(hint["id"])
        print()

    if noise_firing:
        print("🟡 KNOWN-NOISE, STILL FIRING (should be silenced):")
        seen = set()
        for a in noise_firing:
            print(line(a))
            entry = match_noise(a["labels"])
            if entry and entry["id"] not in seen:
                print(f"      → {entry['note']}")
                seen.add(entry["id"])
        print()

    if silenced:
        print("🔇 SILENCED (known/tracked — no action):")
        for a in silenced:
            l = a["labels"]
            print(f"  {l.get('alertname')} @ {l.get('instance','?')} {l.get('name','')}".rstrip())
        print()

    if inhibited:
        print("⚫ INHIBITED:")
        for a in inhibited:
            l = a["labels"]
            print(f"  {l.get('alertname')} @ {l.get('instance','?')} {l.get('name','')}".rstrip())
        print()

    if not alerts:
        print("✅ Nothing firing.")

    return 2 if needs else 0


if __name__ == "__main__":
    sys.exit(main())
