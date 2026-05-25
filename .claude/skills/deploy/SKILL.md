---
name: deploy
description: Safely deploy infrastructure changes via `make apply`. Renders configs, runs terraform plan, pauses for explicit user confirmation, applies, then verifies the fleet with the health-check logic. Use when the user wants to push pending changes to the infrastructure. Always pauses before applying — never auto-applies.
---

# Deploy

Safely deploy infrastructure changes. This skill is **always safe to run** — it never makes destructive changes without showing the user what will happen and waiting for confirmation.

## Source of truth

- `inventory/inventory.yml` — current set of servers (`core`, `ixp`, `vlt` groups). Servers change over time; never hard-code.
- `secrets/secrets.yml` — encrypted with Ansible Vault; `.password` file in repo root must exist.
- `CLAUDE.md` — full project context. Read it if you need details on a specific component.

## Phases

Run sequentially. Stop and ask the user if any phase produces unexpected output.

### Phase 1 — Pre-flight checks

Run these in parallel and surface anything notable to the user:

```bash
git status --short
git log -1 --oneline
test -f .password && echo "vault password present" || echo "MISSING .password file"
ansible-inventory -i inventory/inventory.yml --list 2>/dev/null \
  | jq -r '[.core.hosts[]?, .ixp.hosts[]?, .vlt.hosts[]?] | "Fleet: \(length) hosts"'
```

Decision rules:
- **No `.password` file** → stop. The user must create it before deploying.
- **Dirty working tree** with template/inventory/terraform changes → show the diff and ask the user to confirm they want to deploy uncommitted changes.
- **Dirty working tree** with only unrelated changes (e.g. notes, docs) → proceed but mention it.

### Phase 2 — Take a baseline health snapshot

Capture pre-deploy state so we can diff it later. Save to `/tmp/deploy-baseline.txt`:

```bash
{
  ansible -i inventory/inventory.yml all \
    -a 'docker ps --format "{{.Names}}\t{{.Image}}\t{{.Status}}"' --one-line 2>/dev/null
} > /tmp/deploy-baseline.txt
```

### Phase 3 — Render and validate

```bash
make render
```

`make render` regenerates `.rendered/` and the Terraform wiring files (`terraform/docker-providers.tf`, `terraform/ixp.tf`, `terraform/vlt.tf`, `terraform/terraform.tfvars`). If it fails, surface the error.

**Common failure: Terraform provider cache is out of date.** When a Renovate batch bumps `kreuzwerker/docker`, `vultr/vultr`, or other Terraform providers, `make render` reports `Required plugins are not installed` / `there is no package for registry.terraform.io/X/Y vX.Y.Z cached in .terraform/providers`, followed by `VLT BIRD configs may be missing IP addresses` because the render script can't read Terraform outputs. This is **expected** after provider bumps and is safe to fix automatically — `terraform init -upgrade` only downloads providers to the local `.terraform/providers/` cache; it does not touch infrastructure. Run it and re-render:

```bash
terraform -chdir=./terraform init -upgrade
make render
```

Other failure modes (missing secret key, undefined template variable, VLT host not in Terraform state) require human attention — stop and surface the error. Common causes are in `CLAUDE.md` under "Troubleshooting".

### Phase 4 — Plan

```bash
terraform -chdir=./terraform plan
```

Show the plan output to the user. Summarize the meaningful parts (containers added/removed/changed, image bumps, network changes). If the plan is empty (`No changes`), tell the user — the deploy is a no-op at the Terraform level, but `make apply` will still re-sync configs and may restart containers if their rendered config changed. Ask whether to proceed.

### Phase 5 — Confirm

**Stop here. Ask the user explicitly: "Apply this plan? (yes/no)"**

Do not proceed without an affirmative answer in this turn. If the user wants changes, return to Phase 3.

### Phase 6 — Apply

```bash
make apply
```

This runs `render` → `sync-config` → `terraform apply -auto-approve`. Stream output to the user. If it fails partway:
- Note which step failed (`sync-config` is Ansible/rsync; `apply` is Terraform).
- Do not retry automatically. Show the error and let the user decide.

### Phase 7 — Verify

Invoke the same checks as `/health-check`:
1. Fleet container status (compare against `/tmp/deploy-baseline.txt` to highlight what actually changed).
2. ClickHouse pipeline freshness on the core server.
3. BIRD service status on `ixp:vlt`.

**Wait ~30 seconds** after `make apply` returns before running pipeline freshness checks — containers may still be restarting and Kafka consumers need a moment to catch up.

Report:
- Containers added / removed / image-changed (from the diff).
- Anything that came back unhealthy or is missing.
- Pipelines that are not flowing.

### Phase 8 — Cleanup

```bash
rm -f /tmp/deploy-baseline.txt
```

## Common deploy variants

- **Config-only change** (no Terraform diff): the user may prefer the faster path described in `CLAUDE.md` → "Config-only changes (no Terraform)". Offer this if the plan is empty: `make sync-config` + `docker restart <container>`.
- **BIRD-only change**: not handled by `/deploy`. Point the user at `make sync-bird` (requires sudo password).
- **WireGuard-only change**: not handled by `/deploy`. Point the user at `make sync-wireguard` (requires sudo password).
- **New VLT server**: this skill is not the right tool. Point the user at `make vlt` (full sequence) or the step-by-step in `CLAUDE.md`.

## Safety rules

- **Never** run `make apply` or `terraform apply` before showing the plan and getting explicit user approval in Phase 5.
- **Never** run `terraform destroy`, `make destroy`, or `make vlt-prune` from this skill.
- **Never** edit `secrets/secrets.yml` from this skill.
- **Never** skip Phase 4 (plan). Even for "just a quick config change", show the plan.
- If the user says "just apply it", still show them the plan summary, then proceed once they confirm.
