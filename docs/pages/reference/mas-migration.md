# MAS Migration Runbook (syn2mas)

One-time procedure to migrate Synapse from native Auth0 OIDC to delegated authentication via the Matrix Authentication Service (MAS) using the upstream `syn2mas` tool. Performed 2026-04-20; kept here for reference and any future re-deployment.

For day-to-day MAS admin operations and the high-level topology, see [`CLAUDE.md`](https://github.com/nxthdr/infrastructure/blob/main/CLAUDE.md) → "Matrix Authentication Service (MAS)".

## Gotchas

Two specific issues that bit us during the original migration:

- **Distroless MAS image + IPv6 DB URI.** The MAS container image is distroless; `syn2mas --synapse-database-uri` with an IPv6-in-brackets URL silently falls back to localhost. Pass DB config via libpq `PG*` env vars and use the bare URI `postgresql:`.
- **`oidc_providers` needs to be visible to syn2mas.** The tool requires the pre-migration `oidc_providers:` block in `homeserver.yaml` to map legacy users onto MAS upstream providers. Once MSC3861 is merged into `homeserver.yaml.j2`, reconstruct a temporary `homeserver.yaml` that still has the old `oidc_providers:` block and feed that to `syn2mas`. The corresponding MAS upstream provider needs a matching `synapse_idp_id: "oidc-<idp_id>"` field.

## Procedure

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

## Rollback

If MAS goes wrong and you need to revert to Auth0-direct:

1. Restore the Postgres dump from step 1 above (this rolls back the syn2mas data changes).
2. Revert the `experimental_features.msc3861:` block in `homeserver.yaml.j2`; restore the `oidc_providers:` block and `registration_shared_secret:` line from git.
3. `make apply` + `docker restart synapse`.
4. MAS container can keep running or be removed.
