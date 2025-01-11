.PHONY: sync-cert
sync-cert:
	scp -r root@core.infra.nxthdr.dev:/home/nxthdr/proxy/data/caddy/certificates/ root@ams.scw.infra.nxthdr.dev:/home/nxthdr/proxy/data/caddy/

.PHONY: sync-config
sync-config:
	ANSIBLE_DISPLAY_SKIPPED_HOSTS=false ansible-playbook -e @secrets/secrets.yml -i inventory/ --ask-vault-pass sync-config.yml

.PHONY: apply
apply: sync-config
	terraform apply -auto-approve -parallelism=1

.PHONY: destroy
destroy:
	terraform destroy