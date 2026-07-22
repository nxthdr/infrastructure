---
name: check-alerts
description: Fetch and triage the nxthdr platform's currently-firing alerts from Alertmanager, the agent-friendly way — no vault, no basic-auth. Separates "needs attention now" from known-noise (Frankfurt LocIX BGP outage, VLT node OOM flaps) and from already-silenced alerts, and shows how to create/renew a silence. Use when the user asks what alerts are open/firing, to check the alert room, or to investigate a page. Read-only by default (silencing requires explicit confirmation).
---

# Check Alerts

Read the live alert state from Alertmanager and report a triaged summary: what genuinely needs attention vs. known-noise vs. already silenced.

**Relationship to `health-check`:** `health-check` actively probes the fleet ("is everything OK right now?"). This skill reads what the **monitoring system itself** is reporting ("what is Alertmanager firing, and does any of it matter?"). When investigating a page, start here; drop into `health-check` or host-level digging for anything that lands in NEEDS ATTENTION.

## Fetching alerts (no auth needed)

Alertmanager (`prom/alertmanager`, container `alertmanager` on `coreams01`) has **no host port and no public basic-auth on the internal API**. The public endpoint `https://alertmanager.nxthdr.dev` *does* require basic auth whose password lives in the vault — and **decrypting `secrets.yml` is blocked by the auto-classifier**. So don't go that route. Query the internal v2 API from the core host instead.

Discover the container's IPv6 dynamically (don't hard-code it — it comes from `terraform/coreams01.tf` and could change) and pipe straight into the triage script:

```bash
ssh nxthdr@ams01.core.infra.nxthdr.dev \
  'IP=$(docker inspect -f "{{range .NetworkSettings.Networks}}{{.GlobalIPv6Address}}{{end}}" alertmanager); curl -s "http://[$IP]:9093/api/v2/alerts"' \
  | python3 .claude/skills/check-alerts/triage.py
```

`triage.py` reads the v2 alerts JSON on stdin (stdlib only) and prints:
- **🔴 NEEDS ATTENTION** — unsilenced and *not* known-noise. These are real.
- **🟡 KNOWN-NOISE, STILL FIRING** — matches a recurring non-actionable class but isn't silenced (usually because a silence expired). Recommend (re-)silencing.
- **🔇 SILENCED** / **⚫ INHIBITED** — tracked, no action.

It exits `2` if anything is in NEEDS ATTENTION, else `0`.

**Why the v2 API and not `amtool`:** `amtool alert query` hides silenced alerts by default, so it can't tell you "5 known alerts are correctly silenced." The v2 API returns everything with `status.silencedBy`/`inhibitedBy` intact, which is what the triage depends on. (`docker exec alertmanager amtool alert query -o simple` is still a fine quick human peek at *only* what's active.)

## Known-noise classes (kept in `triage.py`)

The script encodes the recurring non-actionable alerts so they don't get re-investigated every time. Keep it in sync with `docs/pages/reference/alert-silences.md` and the `project_recurring_alerts` memory:

| Class | Match | Verdict |
|---|---|---|
| Frankfurt LocIX BGP | `BGP_Session_Down` @ `ixpfra01`, session `HE`/`Cloudflare`/`LocIXRS[0-9]` | Upstream/IXP outage. Silence it. |
| VLT node OOM | `Host_Out_Of_Memory` @ `vlt*` | Benign flap — full-table BGP + BMP dual-RIB on ~1GB boxes; bird ~390MB by design. Act only if a container is OOM-killed; real fix = resize. |

When you add or retire a recurring alert, edit the `KNOWN_NOISE` list at the top of `triage.py`.

## Silences

List current silences (to spot ones expiring soon — the FRA silence needs periodic renewal):

```bash
ssh nxthdr@ams01.core.infra.nxthdr.dev \
  'IP=$(docker inspect -f "{{range .NetworkSettings.Networks}}{{.GlobalIPv6Address}}{{end}}" alertmanager); curl -s "http://[$IP]:9093/api/v2/silences"'
```

**Creating or renewing a silence is a state change — confirm with the user first**, then POST to the same internal API. Full procedure and matcher reference: `docs/pages/reference/alert-silences.md`. The Frankfurt LocIX silence (the one that recurs) is:

```bash
ssh nxthdr@ams01.core.infra.nxthdr.dev 'bash -s' <<'REMOTE'
IP=$(docker inspect -f "{{range .NetworkSettings.Networks}}{{.GlobalIPv6Address}}{{end}}" alertmanager)
NOW=$(date -u +%Y-%m-%dT%H:%M:%S.000Z); END=$(date -u -d "+30 days" +%Y-%m-%dT%H:%M:%S.000Z)
curl -s -X POST "http://[$IP]:9093/api/v2/silences" -H 'Content-Type: application/json' -d "{
  \"matchers\":[
    {\"name\":\"alertname\",\"value\":\"BGP_Session_Down\",\"isRegex\":false,\"isEqual\":true},
    {\"name\":\"instance\",\"value\":\"ixpfra01\",\"isRegex\":false,\"isEqual\":true},
    {\"name\":\"name\",\"value\":\"HE|Cloudflare|LocIXRS[0-9]\",\"isRegex\":true,\"isEqual\":true}],
  \"startsAt\":\"$NOW\",\"endsAt\":\"$END\",
  \"createdBy\":\"claude\",\"comment\":\"Known LocIX/iFog FRA outage; renewing expired silence. 30d.\"}"
REMOTE
```

Always scope silences to the specific instance/session and set a bounded expiry with a comment.

## What this skill does NOT do

- Does not silence, restart, or remediate anything without explicit user confirmation.
- Does not decrypt the vault or touch the public basic-auth endpoint (blocked/unnecessary).
- Does not deep-dive hosts — for that, hand off to `health-check`, `docker logs <name>`, or host-level commands on the affected instance.
