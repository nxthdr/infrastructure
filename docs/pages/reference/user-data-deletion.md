# User Data Deletion (GDPR Erasure)

Operator runbook for fulfilling a **right-to-erasure** request (GDPR Art. 17) — either
when a user emails `admin@nxthdr.dev` asking for deletion, or when they delete their
account. The [public privacy policy](https://docs.nxthdr.dev/docs/reference/privacy/)
promises this right; this page is how an operator actually delivers it.

!!! warning "This is a destructive, mostly-irreversible procedure"
    Most steps hard-delete rows or deactivate accounts. Work through the steps **in
    order** — you cannot cleanly delete a user who still has live BGP announcements or a
    connected VPN node. Capture the read-only "before" state (Step 2) **before** you
    delete anything; some of it (the probing `user_id`) is needed later and cannot be
    recovered once deleted.

## Guiding principle: two classes of data

This is the backbone of the whole procedure. nxthdr holds two kinds of user data and
treats them differently:

- **Identity / account data → erase.** Auth0 profile and email, the raw Auth0 `sub`
  stored in peerlab-gateway, ASN/prefix leases, per-user limits, the Headscale node and
  OIDC user, and (if present) the Matrix account. This is unambiguously personal data and
  is hard-deleted.
- **Pseudonymous research data → dissociate, don't purge.** The probe replies in
  ClickHouse (`saimiris.replies`) are linked to a person *only* indirectly, via the
  source IPv6 prefix. They are [PDDL](https://opendatacommons.org/licenses/pddl/) open
  research data and fall under the GDPR Art. 17(3)(d) scientific-research carve-out. We
  delete the **linkage**, not the measurements: once the gateway mapping is gone, the rows
  are just "measurements from prefix X", attributable to no natural person. The **7-day
  TTL** then expires them anyway.

Two facts make the research side tractable:

- **7-day TTL** on `saimiris.replies` (`TTL date + INTERVAL 7 DAY DELETE`) — live
  measurement data self-expires within a week. "Delete from ClickHouse" is mostly *stop
  new inserts + wait out the TTL*.
- **Already-published data can't be recalled.** Anything exported or cited under PDDL is
  out there; GDPR Art. 17(2) only requires *reasonable* steps. See
  [Boundaries](#boundaries-what-deletion-does-not-cover).

## How the data is actually linked

Everything keys off a single pseudonymous identifier, the **`user_hash`**:

```
user_hash = SHA256(auth0_sub)        # hex, 64 chars, NO salt
```

Both gateways compute it identically and with no salt, so **one person has one
`user_hash` everywhere**. That is the key you use throughout this runbook.

| System | What it holds | Keyed by | Erasure action |
|---|---|---|---|
| **Auth0** | identity, email, `sub`, profile | the account | delete user (Management API / dashboard) |
| **peerlab-gateway** PG (`peerlab_gateway`) | `user_asn_mappings` — ASN, `max_leases`, **raw Auth0 `sub`** in `user_id`; `prefix_leases` — leased /48s (soft-deleted via `revoked_at`) | `user_hash` | remove ROAs, hard-delete rows |
| **saimiris-gateway** PG (`saimiris`) | `user_id_mappings` (`user_hash`↔32-bit `user_id`), `user_limits` (quota), `measurement_tracking` | `user_hash` | hard-delete rows |
| **Headscale** (`headscale` container) | VPN node + OIDC user | OIDC `sub` / email | deregister node, destroy user |
| **Securebit** (external) | RPKI ROAs for leased /48s | prefix | remove ROA per leased prefix |
| **ClickHouse** `saimiris.replies` | probe replies — **only** `probe_src_addr`, no `user_hash`, no `measurement_id` | source prefix | **dissociate** (delete gateway mapping); 7-day TTL expires rows |
| **MAS / Synapse** (`mas` / `synapse`) | Matrix account, if the user has one | MXID ↔ Auth0 `sub` | conditional: lock in MAS + deactivate (erase) in Synapse |
| **Loki** (`loki`) | container logs containing `sub` / IPs | — | nothing — `retention_period: 7d` self-expires |
| **Postgres backups** | residual copies of every table above | — | purge retained dumps (see [Backups](#step-7-logs-and-backups)) |

!!! note "Why ClickHouse needs no row-level delete"
    `saimiris.replies` has **no `user_hash` and no `measurement_id` column** — only
    `probe_src_addr`. The *only* path from a reply back to a person is
    `probe_src_addr` → (deterministic prefix math) → `user_id` → `user_id_mappings.user_hash`
    → (Auth0) → person. Deleting the `user_id_mappings` row **and** the Auth0 user removes
    that path. After that the rows are unattributable, and the TTL clears them within 7
    days. We deliberately do **not** run a heavy `ALTER … DELETE`.

## Prerequisites

- SSH access to the core server: `ssh nxthdr@ams01.core.infra.nxthdr.dev`.
- The requester's **Auth0 `sub`** (e.g. `auth0|0123456789abcdef`). Verify it is the
  authenticated user — see Step 1.
- Postgres runs in the `postgresql` container on the core; databases `peerlab_gateway`
  and `saimiris` share host `[2a06:de00:50:cafe:10::116]:5432`.
- Securebit web-UI credentials and the MAS/Synapse admin token live in
  `secrets/secrets.yml` (`securebit.*`, `mas.synapse_shared_secret`). Decrypt with
  `make edit-secrets` in the infrastructure repo if you need them.

---

## Step 1 — Verify the requester

Erasure must only be performed for the **authenticated user**. Confirm the request comes
from the email on the Auth0 account, or that the requester can prove control of the
account (logged-in session, signed request). Record the Auth0 `sub` you will act on.

```bash
export SUB='auth0|0123456789abcdef'    # the verified Auth0 subject
```

## Step 2 — Compute the `user_hash` and capture the "before" state

The `user_hash` is the SHA-256 of the **exact** `sub` string, with no trailing newline:

```bash
export USER_HASH=$(printf '%s' "$SUB" | sha256sum | awk '{print $1}')
echo "$USER_HASH"
```

Now record everything you are about to delete. **Do this before any delete** — the
probing `user_id` cannot be recovered afterwards and you need it to reason about (and
optionally verify) the ClickHouse rows.

=== "peerlab-gateway"

    ```bash
    docker exec -i postgresql psql -U postgres -d peerlab_gateway <<SQL
    SELECT user_hash, user_id, asn, max_leases FROM user_asn_mappings WHERE user_hash = '$USER_HASH';
    SELECT prefix::text, start_time, end_time, revoked_at FROM prefix_leases WHERE user_hash = '$USER_HASH';
    SQL
    ```

    Note the **ASN** and **every `prefix`** (including already-revoked ones) — you need the
    prefixes for the Securebit ROA removal in Step 3.

=== "saimiris-gateway"

    ```bash
    docker exec -i postgresql psql -U postgres -d saimiris <<SQL
    SELECT user_hash, user_id FROM user_id_mappings WHERE user_hash = '$USER_HASH';
    SELECT probe_limit FROM user_limits WHERE user_hash = '$USER_HASH';
    SELECT count(*), min(created_at), max(updated_at) FROM measurement_tracking WHERE user_hash = '$USER_HASH';
    SQL
    ```

    Note the **`user_id`** (a 32-bit integer). The user's probing source prefixes are
    *derived* from it — `agent_prefix` with `user_id` carved into the 32 bits after the
    agent prefix length (e.g. an agent `/48` yields the user a `/80`). Keep it for the
    optional ClickHouse awareness query in Step 5.

## Step 3 — Tear down active resources

Order matters: stop the user from announcing/probing before you delete the records that
authorize them.

### 3a. Peering — remove ROAs, then leases

For **each** prefix the user leased (from Step 2), remove its RPKI ROA in the
[Securebit](https://www.securebit.cloud/) web UI (log in with `securebit.*` from
`secrets.yml`; this is the same UI the gateway scrapes). This withdraws the authorization
for AS215011 to originate that /48.

!!! info "Why this is a manual UI step"
    peerlab-gateway only *adds/ensures* ROAs automatically; its `DELETE /api/user/prefix/{prefix}`
    endpoint actually **re-adds** the ROA before soft-deleting the lease (to keep in-flight
    announcements valid). There is no operator endpoint to remove a ROA, so do it in the
    Securebit UI directly. ROAs authorize the nxthdr origin ASN, not the user, so they are
    not personal data — this is resource hygiene, returning the prefix to a clean state.

The gateway hard-deletes in Step 4 (which also frees the ASN back to the pool).

### 3b. Headscale — deregister node and OIDC user

The peering VPN runs on Headscale (Auth0 OIDC). Remove the user's node(s) and their OIDC
user record (nodes would otherwise linger until the 180-day expiry, and the user record
persists indefinitely):

```bash
docker exec headscale headscale users list                       # find the user (by email)
docker exec headscale headscale nodes list --user <user-id>      # find their node(s)
docker exec headscale headscale nodes delete --identifier <node-id>
docker exec headscale headscale users destroy --identifier <user-id>
```

!!! tip "Confirm subcommands against the running Headscale version"
    Headscale's CLI surface changes between releases. If `--identifier` / `destroy` differ,
    check `docker exec headscale headscale users --help` and `… nodes --help`.

### 3c. Probing — nothing to stop server-side

Probing is request-driven: the user submits to saimiris-gateway, which publishes to Kafka
for the agents. There is no long-running per-user process to stop. Their quota and
in-flight tracking are removed by the Step 4 deletes.

## Step 4 — Delete account records from both gateways

Hard-delete every per-user row. These are plain `DELETE`s (the soft-delete `revoked_at`
flag on leases is for normal lifecycle, not erasure).

=== "peerlab-gateway"

    ```bash
    docker exec -i postgresql psql -U postgres -d peerlab_gateway <<SQL
    BEGIN;
    DELETE FROM prefix_leases      WHERE user_hash = '$USER_HASH';   -- active + revoked
    DELETE FROM user_asn_mappings  WHERE user_hash = '$USER_HASH';   -- frees the ASN, removes raw Auth0 sub
    COMMIT;
    SQL
    ```

=== "saimiris-gateway"

    ```bash
    docker exec -i postgresql psql -U postgres -d saimiris <<SQL
    BEGIN;
    DELETE FROM measurement_tracking WHERE user_hash = '$USER_HASH';
    DELETE FROM user_limits          WHERE user_hash = '$USER_HASH';
    DELETE FROM user_id_mappings     WHERE user_hash = '$USER_HASH';   -- severs ClickHouse attribution
    COMMIT;
    SQL
    ```

    !!! note "Legacy `probe_usage` table"
        Older deployments may still have a deprecated `probe_usage` table (superseded by
        `measurement_tracking`). If it exists, delete from it too:
        `DELETE FROM probe_usage WHERE user_hash = '$USER_HASH';`

Deleting `user_asn_mappings` removes the **raw Auth0 `sub`** (stored there for email
lookups) — the only place outside Auth0 that holds it. Deleting `user_id_mappings`
removes the `user_id ↔ user_hash` link, which is what severs ClickHouse attribution.

## Step 5 — ClickHouse: dissociate, let the TTL expire

**No action is required in ClickHouse.** Once Step 4 removed `user_id_mappings` (and Step
6 removes the Auth0 `sub`), there is no longer any stored path from a `probe_src_addr`
back to a person. The replies are now pseudonymous open data, and the 7-day TTL expires
the live rows.

!!! warning "Do not run `ALTER … DELETE`"
    Deleting by source prefix is a heavy mutation across a ~half-billion-row table and is
    unnecessary under the dissociate approach. Only consider it if a future policy decision
    explicitly opts into aggressive purging.

??? info "Optional: situational awareness query (read-only)"
    The user's source prefix is `agent_prefix` with `user_id` placed in the 32 bits after
    the prefix length. For a unicast agent `/48`, that yields a `/80`. If you computed the
    user's prefix from Step 2's `user_id` (e.g. `2a0e:97c0:8a0:1234:5678::/80`), you can see
    what will expire:

    ```sql
    SELECT count(), min(date), max(date)
    FROM saimiris.replies
    WHERE probe_src_addr BETWEEN toIPv6('2a0e:97c0:8a0:1234:5678::')
                             AND toIPv6('2a0e:97c0:8a0:1234:5678:ffff:ffff:ffff');
    ```

    This is informational only — the rows expire on their own within 7 days.

!!! note "On the deterministic hash"
    Because `user_id` is *derived* from `user_hash` (and `user_hash` from `sub`) with no
    salt, the prefix is reproducible by anyone who already knows the Auth0 `sub`. That is a
    *confirmation* path, not re-identification of an unknown person — and it closes entirely
    once the Auth0 user is deleted in Step 6. This is the practical basis for treating the
    data as dissociated.

## Step 6 — Erase identity

### 6a. Auth0 (always)

Delete the Auth0 user. This removes the email, profile, and `sub`, and closes the last
`sub → user_hash` re-link path.

- **Dashboard:** Auth0 → User Management → Users → find by email/`sub` → **Delete User**.
- **Management API:** `DELETE /api/v2/users/{sub}` with an M2M token (URL-encode the `|`
  in the `sub`).

### 6b. Matrix / MAS — only if the user has a Matrix account

Matrix accounts share the Auth0 identity but not every user has one. If they do:

```bash
# 1. Find the MXID localpart from the MAS database (no `list-users` CLI exists).
#    Confirm column names against your MAS version.
docker exec -i postgresql psql -U postgres -d mas <<SQL
SELECT u.username
FROM users u
JOIN upstream_oauth_links l ON l.user_id = u.id
WHERE l.subject = '$SUB';
SQL

# 2. Lock the account and kill sessions in MAS (prevents re-login).
docker exec mas mas-cli manage lock-user <username>
docker exec mas mas-cli manage kill-sessions <username>

# 3. Deactivate + erase in Synapse (redacts the account). Token = mas.synapse_shared_secret.
TOKEN='<mas.synapse_shared_secret>'
curl -s "http://[2a06:de00:50:cafe:10::1008]:8008/_synapse/admin/v1/deactivate/@<username>:nxthdr.dev" \
  -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"erase": true}'
```

## Step 7 — Logs and backups

- **Loki** is configured with `retention_period: 7d` and `retention_enabled: true`, so
  container logs containing the `sub` or source IPs self-expire within a week. No manual
  action.
- **Postgres backups: these now exist and they do contain the erased user.**
  `make backup-postgres` (see the infrastructure repo) takes a `pg_dumpall` of
  `mas`, `peerlab_gateway`, `saimiris` and `synapse` to the operator's machine and
  **retains the most recent 14 dumps**. Every row you deleted in Step 4, and the
  Auth0 `sub` in `user_asn_mappings`, still exists in any dump taken before the
  erasure.

    The retention window is **count-based, not time-based** — 14 dumps, taken
    manually — so it does *not* expire on a predictable schedule the way the Loki
    and ClickHouse TTLs do. You cannot honestly tell a requester "your data is
    gone in 7 days" while a dump from last month sits on a laptop.

    So erasure is **not complete** until the retained dumps are dealt with. Do one
    of these, and record which:

    1. **Purge and re-dump** (simplest, recommended): delete the existing dumps and
       take a fresh one *after* the Step 4 deletes, so no retained copy contains the
       user.
       ```bash
       rm -f backups/postgres/postgresql-*.sql.gz
       make backup-postgres
       ```
       The cost is losing point-in-time recovery depth, which for a manual backup is
       a reasonable trade against a compliance promise.
    2. **Wait out the rotation** — only defensible once dumps are automated on a
       known schedule, so the window is a stated number of days. Not the case today.

    When backups move off-host or become automated (`infrastructure#16`), this
    section and the [privacy policy](https://docs.nxthdr.dev/docs/reference/privacy/)
    must state the rotation window explicitly, and deletion "completes" only after
    it elapses.

## Step 8 — Confirm and tombstone

Verify the deletes (all counts should be `0`):

```bash
docker exec -i postgresql psql -U postgres -d peerlab_gateway -c \
  "SELECT (SELECT count(*) FROM user_asn_mappings WHERE user_hash='$USER_HASH') AS asn_rows,
          (SELECT count(*) FROM prefix_leases    WHERE user_hash='$USER_HASH') AS lease_rows;"

docker exec -i postgresql psql -U postgres -d saimiris -c \
  "SELECT (SELECT count(*) FROM user_id_mappings   WHERE user_hash='$USER_HASH') AS id_rows,
          (SELECT count(*) FROM user_limits        WHERE user_hash='$USER_HASH') AS limit_rows,
          (SELECT count(*) FROM measurement_tracking WHERE user_hash='$USER_HASH') AS track_rows;"
```

Then:

- **Notify the requester** that erasure is complete, and explain the two boundaries below
  (TTL window for live measurements; published data cannot be recalled).
- **Keep a minimal, irreversible tombstone** as compliance proof: record the `user_hash`,
  the date, and the request reference — **nothing else** (no email, no `sub`). The hash
  alone is not directly identifying once Auth0 is deleted, and serves to demonstrate the
  request was fulfilled.

---

## Boundaries — what deletion does *not* cover

- **Already-published / exported research data.** Datasets exported or cited under PDDL
  cannot be recalled. GDPR Art. 17(2) only requires reasonable steps; we stop new linkage
  and let live data expire, but cannot un-publish.
- **The ≤7-day TTL window.** Live `saimiris.replies` rows remain (unattributable) until the
  TTL expires them — up to 7 days after the last measurement.
- **Backups.** Local `pg_dumpall` copies exist (`make backup-postgres`, 14 retained) and
  contain the erased rows. Erasure is only complete once those are purged — see Step 7.
  There is no automated, time-bounded rotation window yet (`infrastructure#16`).

## Verifying the runbook against a test account

Before relying on this procedure, validate it end-to-end with a throwaway Auth0 account
(do **not** test against a real user):

1. Create a test Auth0 user; log into nxthdr.dev with it.
2. Exercise the platform: request an ASN, lease a prefix (creates a ROA), connect the
   PeerLab VPN, and submit a small probing measurement.
3. Confirm rows exist: run the Step 2 queries (non-zero), and the Step 5 awareness query
   (some replies after a probe cycle).
4. Run Steps 1–8.
5. Confirm: Step 8 counts are all `0`; the ROA is gone from Securebit; the Headscale node
   and user are gone; the Auth0 user is deleted; and the test prefix's replies stop
   growing and disappear within 7 days.

---

## Toward automation — admin endpoint design (planned)

Today this is a manual runbook (correct, auditable, near-zero effort). The next step —
dovetailing with the admin-endpoint work in `roadmap#16` / `roadmap#25` — is to automate
the per-gateway teardown so an operator (and eventually the user) triggers it with one
call.

**Shape:**

- **Per-gateway admin endpoint**, reusing each gateway's existing service/agent bearer
  auth (peerlab `/service/*`, saimiris `/agent-api/*`) or a dedicated admin scope:
  - `DELETE /service/user/{user_hash}` on **peerlab-gateway** → removes ROAs for the
    user's leased prefixes (Securebit), then hard-deletes `prefix_leases` +
    `user_asn_mappings`.
  - `DELETE /admin/user/{user_hash}` on **saimiris-gateway** → hard-deletes
    `measurement_tracking` + `user_limits` + `user_id_mappings` (+ legacy `probe_usage`).
  - Both **idempotent** (deleting an already-deleted user is a no-op `200`), returning a
    summary of what was removed for the audit log.
- **Orchestrator** (a small admin script, or the dashboard backend) runs the full ordered
  flow: verify → peerlab delete → saimiris delete → Headscale deregister → Auth0 delete →
  optional Matrix deactivate → tombstone. ClickHouse needs no call (dissociation + TTL).
- **Partial-failure handling:** the orchestrator records per-step success and is safe to
  re-run; because every step is idempotent, a retry converges. Manual steps that have no
  API yet (Securebit ROA removal until automated, Matrix deactivation) stay in this runbook
  as documented fallbacks.
- **Self-service (eventually):** a "Delete my account" button in the dashboard calls the
  orchestrator with the user's own JWT; the backend derives `user_hash` from the verified
  `sub` server-side, so a user can only ever delete themselves.

The endpoints belong with the broader admin surface tracked in `roadmap#16` / `roadmap#25`;
this section is the erasure-specific contract they must satisfy.
