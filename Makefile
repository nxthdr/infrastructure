.PHONY: sync-cert
sync-cert:
	scp -r root@core.infra.nxthdr.dev:/home/nxthdr/proxy/data/caddy/certificates/ root@ams.scw.infra.nxthdr.dev:/home/nxthdr/proxy/data/caddy/
	scp -r root@core.infra.nxthdr.dev:/home/nxthdr/proxy/data/caddy/certificates/ root@waw.scw.infra.nxthdr.dev:/home/nxthdr/proxy/data/caddy/

.PHONY: sync-config
sync-config:
	rsync -r files/core/* nxthdr@core.infra.nxthdr.dev:~
	rsync -r files/ams-sw/* nxthdr@ams.scw.infra.nxthdr.dev:~
	rsync -r files/waw-sw/* nxthdr@waw.scw.infra.nxthdr.dev:~

.PHONY: apply
apply: sync-config
	terraform apply -auto-approve -parallelism=1

.PHONY: destroy
destroy:
	terraform destroy