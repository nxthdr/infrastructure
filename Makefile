.PHONY: sync
sync: 
	rsync -r files/* core.infra.nxthdr.dev:~/nxthdr

.PHONY: apply
apply: sync
	terraform apply -auto-approve -parallelism=1

.PHONY: destroy
destroy:
	terraform destroy