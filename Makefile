.PHONY: sync-cert
sync-cert:
	scp -r root@ams01.core.infra.nxthdr.dev:/home/nxthdr/proxy/data/caddy/certificates/ root@ams01.scw.infra.nxthdr.dev:/home/nxthdr/proxy/data/caddy/

.PHONY: edit-secrets
edit-secrets:
	ansible-vault edit secrets/secrets.yml

.PHONY: sync-wireguard
sync-wireguard:
	ansible-playbook -i inventory/ -e "base_dir=$$(pwd)" -e @secrets/secrets.yml --ask-become-pass --ask-vault-pass playbooks/sync-wireguard.yml

.PHONY: sync-bird
sync-bird:
	ansible-playbook -i inventory/ -e "base_dir=$$(pwd)" -e @secrets/secrets.yml --ask-become-pass --ask-vault-pass playbooks/sync-bird.yml

.PHONY: template
template:
	ANSIBLE_DISPLAY_SKIPPED_HOSTS=false \
	ansible-playbook -e "base_dir=$$(pwd)" -e @secrets/secrets.yml -i inventory/ --ask-vault-pass playbooks/template.yml

.PHONY: sync-config
sync-config: template
	ansible-playbook -e "base_dir=$$(pwd)" -i inventory/ playbooks/sync-config.yml

.PHONY: apply
apply: sync-config
	terraform -chdir=./terraform apply -auto-approve -parallelism=1

.PHONY: destroy
destroy:
	terraform -chdir=./terraform destroy -auto-approve
