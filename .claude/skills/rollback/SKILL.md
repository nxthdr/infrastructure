---
name: rollback
description: Roll back an nxthdr service that broke after an image update, especially services pinned to floating tags (`ghcr.io/nxthdr/*:main`, `*:latest`). Finds the last-good image, pins it in Terraform, applies the rollback scoped to just that service, and verifies. Use when a service is crash-looping or misbehaving after a deploy / image bump and you need to get back to a known-good version.
---

# Rollback

Roll back a single service to a known-good image after an update broke it. This is the companion to `/deploy`: deploy pushes forward, rollback pins back.

## Why rollback is not just "re-apply"

Most nxthdr first-party services track the **floating `:main` tag** with this pattern (e.g. risotto at `terraform/coreams01.tf:610`):

```hcl
data "docker_registry_image" "risotto" {
  name = "ghcr.io/nxthdr/risotto:main"
}
resource "docker_image" "risotto" {
  name          = data.docker_registry_image.risotto.name
  pull_triggers = [data.docker_registry_image.risotto.sha256_digest]
}
```

Two consequences that define this whole procedure:

1. **The running version is not recorded in git.** It's whatever `:main` resolved to at the last apply. There is no commit to `git revert`.
2. **Re-applying does NOT roll back.** The `data` source re-reads the registry every plan, so another `make apply` just re-pulls the same broken `:main`. **To roll back you must repoint the reference at an immutable image** (a digest, or an immutable tag), then apply.

The previous image is almost always still on the host (Docker doesn't auto-prune), and `log_opts` embeds `{{.ImageFullID}}` (e.g. `coreams01.tf:636`), so Loki also has a record of the prior image ID. That's how you recover the last-good target.

## Which services float (and where to edit)

| Service(s) | Tag | File | Pattern | Scope |
|---|---|---|---|---|
| risotto, pesto, saimiris-gateway, peerlab-gateway, nxthdr.dev, blog, docs, peers | `ghcr.io/nxthdr/<svc>:main` | `terraform/coreams01.tf` | data-source + `pull_triggers` → **re-pulls every apply** | core only |
| **saimiris** | `ghcr.io/nxthdr/saimiris:main` | `terraform/modules/vlt-containers/main.tf:181` | data-source + `pull_triggers` | **all VLT hosts** (shared module) |
| tailscale | `tailscale/tailscale:latest` | `terraform/modules/ixp/main.tf:197` | plain `docker_image` (no `pull_triggers`) → only pulls if image absent | all IXP hosts |
| bgpalerter | `nttgin/bgpalerter:latest` | `terraform/coreams01.tf:1193` | plain `docker_image` | core only |

Everything else is pinned to an explicit version (`clickhouse:26.5.1`, `prometheus:v3.12.0`, …). Those don't drift — to roll one back, just `git revert` the version-bump commit and `/deploy`; this skill is overkill for them.

> ⚠️ **Editing a shared module rolls back the whole group.** `modules/vlt-containers` and `modules/ixp` are instantiated per host (`module.vlt_<host>`, `module.ixp_<host>`). There is no per-host override — pinning `saimiris` in the vlt-containers module pins it on **every** VLT host at once. That's usually what you want for a bad image, but say so to the user.

## Source of truth

- `inventory/inventory.yml` — current servers; never hard-code hostnames.
- `terraform/` — the `.tf` files above are where the image reference is pinned.
- `CLAUDE.md` — full project context, SSH patterns, chproxy usage.

## Procedure

### Phase 1 — Confirm the symptom and the service

Identify the broken service and confirm it really is a floating-tag service (table above). A quick look:

```bash
# is it crash-looping / recently exited?
ssh nxthdr@$(ansible-inventory -i inventory/inventory.yml --host coreams01 | jq -r '.ansible_host') \
  'docker ps -a --filter name=<svc> --format "{{.Names}}\t{{.Image}}\t{{.Status}}"'
# why did it break?
ssh nxthdr@<host> 'docker logs --tail 80 <svc>'
```

For a VLT-wide service (`saimiris`) check a couple of VLT hosts via `ansible -i inventory/inventory.yml vlt -a 'docker ps -a --filter name=saimiris ...'`.

If the failure is a **config** problem (bad rendered file), not the image, this skill is the wrong tool — fix the template and `/deploy`. Rollback is for a bad **image**.

### Phase 2 — Find the last-good image (the rollback target)

Try these in order; stop at the first that gives you a digest you trust:

1. **On the affected host — previous image still present (fastest):**
   ```bash
   ssh nxthdr@<host> 'docker images --digests ghcr.io/nxthdr/<svc>'
   ```
   List shows the digests pulled on that host. The one that is **not** currently running (cross-check against the `Image`/ID from Phase 1) is your rollback candidate. Capture the full `ghcr.io/nxthdr/<svc>@sha256:<digest>`.

2. **From Loki** — the prior `{{.ImageFullID}}` appears in historical log lines for the container (logs tagged before the bad deploy), giving you the previous image ID.

3. **From GHCR** — the registry retains every pushed digest. The package page / `gh api` lists them; if CI publishes immutable per-commit tags (e.g. `:sha-<commit>` or a release tag), prefer that over a raw digest — it's human-readable and maps to a commit.

Confirm the candidate predates the breakage (its commit / push time is before the bad one).

### Phase 3 — Pin it in Terraform

For a `:main` (data-source) service, **replace the data-source + `pull_triggers` block with a direct digest pin on the `docker_image` resource**, and delete the `data "docker_registry_image"` block:

```hcl
# ROLLBACK <date>: <reason>. Restore the :main data-source block + pull_triggers once upstream is fixed (issue filed).
resource "docker_image" "risotto" {
  name     = "ghcr.io/nxthdr/risotto@sha256:<good-digest>"
  provider = docker.coreams01
}
```

> ⚠️ **Do NOT just repoint the `data "docker_registry_image"` `name` to a `@sha256:` digest.** Verified 2026-06-24: that data source returns **`404 Not Found`** when given a digest reference (it resolves *tags*, not digests), so `terraform plan` errors out before it can pin anything — and because data sources are read regardless of references, leaving a digest in the block breaks the plan even if nothing uses it. Pin the digest directly on the `docker_image` resource and remove the data source, as above. (An immutable *tag* — e.g. `:sha-abc1234` — would work in the data source, but nxthdr's first-party images don't publish per-commit tags; only `:main` and branch/PR tags exist.)

For a plain `:latest` service (tailscale / bgpalerter), pin the `docker_image` resource `name` directly to a published version tag:

```hcl
resource "docker_image" "bgpalerter" {
  name = "nttgin/bgpalerter:v<known-good>"   # ROLLBACK <date> — was :latest
}
```

For a VLT/IXP module service, edit the shared module file (`modules/vlt-containers/main.tf` / `modules/ixp/main.tf`) — remember this applies to every host in the group.

### Phase 4 — Plan and confirm (scoped, not fleet-wide)

**Do not use `make apply` for a rollback.** `make apply` is untargeted: it re-reads every `:main` data source and would re-pull the latest (possibly broken) image for every *other* first-party service at the same time — exactly the drift that may have caused the incident. Roll back with a **scoped** apply.

```bash
make render        # only if the service mounts rendered config you also changed; image-only rollback can skip
terraform -chdir=./terraform plan \
  -target=docker_image.<svc> -target=docker_container.<svc>
```

Module services use module-qualified targets, one pair per host in the group:

```bash
# saimiris on every VLT host — enumerate module instances from terraform/vlt.tf (module.vlt_<host>)
terraform -chdir=./terraform plan \
  -target='module.vlt_vltcdg01.docker_image.saimiris' -target='module.vlt_vltcdg01.docker_container.saimiris' \
  -target='module.vlt_vltsgp01.docker_image.saimiris' -target='module.vlt_vltsgp01.docker_container.saimiris' \
  # …one pair per VLT host (see `grep '^module' terraform/vlt.tf`)
```

Show the plan. **Confirm it changes only the intended image/container(s)** — the digest goes from the bad one to your target, and nothing else. **Stop and ask the user to approve before applying.**

### Phase 5 — Apply

```bash
terraform -chdir=./terraform apply \
  -target=docker_image.<svc> -target=docker_container.<svc>
```

(Same `-target` set you planned with.) Stream output. If it fails, surface the error; do not retry blindly.

### Phase 6 — Verify

Use the `/health-check` logic, focused on the rolled-back service:

```bash
# container back and stable on the right image
ssh nxthdr@<host> 'docker ps --filter name=<svc> --format "{{.Names}}\t{{.Image}}\t{{.Status}}"'
ssh nxthdr@<host> 'docker logs --tail 40 <svc>'
```

- For pipeline services (risotto/pesto/saimiris): confirm freshness via chproxy per `/health-check` (`bmp.updates`/`flows.records` 5-min window; `saimiris.replies` is bursty → 1-hour window).
- For web services (docs/blog/nxthdr.dev/peers): `curl` the public URL for HTTP 200 (the Prometheus scrape of Caddy `:2019` only proves the process is up, not the content).

### Phase 7 — Record the follow-up

The pin is a **temporary** measure that freezes the service off `:main`. Tell the user explicitly and leave a trail:

- The `# ROLLBACK …` comment in the `.tf` is the marker.
- Once upstream `:main` carries a fix, revert the pin back to the floating tag and `/deploy` so auto-pull resumes.
- A pinned service silently stops receiving updates — note it so it isn't forgotten.

## Emergency host-side fast path (buys time only)

When you can't wait for a Terraform cycle, restart the container on the previous image directly on the host:

```bash
ssh nxthdr@<host>
docker stop <svc>
docker run -d --name <svc> ...   # mirror command/networks/volumes from the .tf, using the good image ID
```

> ⚠️ This drifts from Terraform state. The **next** `terraform apply`/`make apply` will overwrite it with `:main` again. Treat it as a stopgap and still do the Phase 3 pin to make the rollback durable.

## Safety rules

- **Never** roll back with `make apply` or an untargeted `terraform apply` — always scope with `-target` so you don't drag every other `:main` service forward at the same time.
- **Always** show the plan and get explicit user approval before applying (same rule as `/deploy`).
- **Never** run `terraform destroy`, `make destroy`, or `make vlt-prune` from this skill.
- **Never** edit `secrets/secrets.yml` from this skill.
- A digest/tag pin is temporary — always flag the un-pin follow-up so the service doesn't stay frozen off `:main` indefinitely.
