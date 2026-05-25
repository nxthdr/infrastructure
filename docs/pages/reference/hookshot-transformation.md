# Hookshot Webhook Transformation

The Hookshot alertmanager webhook uses a JavaScript transformation function to format alerts with icons and markdown instead of showing raw JSON in the Matrix room. This page covers how to modify that function — a rare operation.

For the alerting pipeline overview and the high-level "what this is" summary, see [`CLAUDE.md`](https://github.com/nxthdr/infrastructure/blob/main/CLAUDE.md) → "Alerting Pipeline".

## Where the transformation lives

The transformation is stored in the Matrix room state event `uk.half-shot.matrix-hookshot.generic.hook` (state_key: `alertmanager`) under the `transformationFunction` field.

Important properties:

- The transformation is **not** stored in any config file — it lives only in Matrix room state (persisted in Synapse's database).
- It **survives** Hookshot restarts and container rebuilds.
- It does **not** survive if the webhook is deleted and recreated (e.g., via `!hookshot webhook alertmanager`).
- There is **no bot command** to set transformations. `!hookshot webhook set-transformation` does not exist — it will be misinterpreted as creating a new webhook named "set-transformation".

## Procedure to modify the transformation

Edit the room state event via the Matrix client-server API.

### 1. Create a temporary admin user via MAS (post-MSC3861)

```bash
ssh nxthdr@ams01.core.infra.nxthdr.dev
# Register a temporary user, then issue an access token with Synapse admin rights
docker exec -ti mas mas-cli manage register-user \
  --yes -p 'TmpPass123!' -e admin_tmp@nxthdr.dev admin_tmp
docker exec -ti mas mas-cli manage issue-compatibility-token \
  --yes-i-want-to-grant-synapse-admin-privileges admin_tmp ADMINTMP01
# Save the printed access_token
```

The legacy `/_synapse/admin/v1/register` endpoint no longer works — Synapse delegates auth to MAS, so `registration_shared_secret` is inert.

### 2. Join the room and get admin power level

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

### 3. PUT the updated state event

The JS function receives `data` as already-parsed JSON; set `result` as the output:

```bash
curl -s "http://[2a06:de00:50:cafe:10::1008]:8008/_matrix/client/v3/rooms/$ROOM_ID/state/uk.half-shot.matrix-hookshot.generic.hook/alertmanager" \
  -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"alertmanager","transformationFunction":"<your JS code as a single-line string>"}'
```

### 4. Restart Hookshot and deactivate the temp user

```bash
docker restart hookshot
curl -s "http://[2a06:de00:50:cafe:10::1008]:8008/_synapse/admin/v1/deactivate/@admin_tmp:nxthdr.dev" \
  -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"erase": true}'
```

## Current transformation output

- 🔴 **FIRING** | AlertName (job) on instance — for critical firing alerts
- 🟡 **FIRING** | AlertName (job) on instance — for warning firing alerts
- ✅ **RESOLVED** | AlertName (job) on instance — for resolved alerts
