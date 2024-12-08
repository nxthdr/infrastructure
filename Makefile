.PHONY: sync
sync:
	rsync -r files/core/* core.infra.nxthdr.dev:~/nxthdr
	rsync -r files/ams-sc/* root@ams.sc.infra.nxthdr.dev:~/nxthdr

.PHONY: apply
apply: sync
	terraform apply -auto-approve -parallelism=1

.PHONY: destroy
destroy:
	terraform destroy