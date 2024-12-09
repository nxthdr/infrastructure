.PHONY: sync
sync:
	rsync -r files/core/* nxthdr@core.infra.nxthdr.dev:~
	rsync -r files/ams-sw/* nxthdr@ams.sw.infra.nxthdr.dev:~
	rsync -r files/waw-sw/* nxthdr@waw.sw.infra.nxthdr.dev:~

.PHONY: apply
apply: sync
	terraform apply -auto-approve -parallelism=1

.PHONY: destroy
destroy:
	terraform destroy