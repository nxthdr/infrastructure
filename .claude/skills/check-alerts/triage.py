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
    {
        "id": "vlt-oom",
        "match": {"alertname": "Host_Out_Of_Memory"},
        "regex": {"instance": r"^vlt"},
        "note": ("Benign flap: VLT probe nodes run full-table BGP + BMP dual-RIB on ~1GB boxes, "
                 "so bird ~390MB (RSS+swap) is by design. Only act if a container is OOM-killed; "
                 "real fix = resize the instance."),
    },
]

SEV_ORDER = {"critical": 0, "error": 1, "warning": 2, "info": 3}
NOW = datetime.now(timezone.utc)


def match_noise(labels):
    for entry in KNOWN_NOISE:
        if any(labels.get(k) != v for k, v in entry["match"].items()):
            continue
        if any(not re.search(rx, labels.get(k, "")) for k, rx in entry.get("regex", {}).items()):
            continue
        return entry
    return None


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
        for a in needs:
            print(line(a))
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
