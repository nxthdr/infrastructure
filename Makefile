.PHONY: sync-cert
sync-cert:
	@scp -r root@ams01.core.infra.nxthdr.dev:/home/nxthdr/proxy/data/caddy/certificates/ root@ams01.scw.infra.nxthdr.dev:/home/nxthdr/proxy/data/caddy/

.PHONY: edit-secrets
edit-secrets:
	@ansible-vault edit --vault-password-file .password secrets/secrets.yml

.PHONY: sync-wireguard
sync-wireguard:
	@ansible-playbook -i inventory/ -e "base_dir=$$(pwd)" -e @secrets/secrets.yml --ask-become-pass --vault-password-file .password playbooks/sync-wireguard.yml

.PHONY: sync-bird
sync-bird:
	@ansible-playbook -i inventory/ -e "base_dir=$$(pwd)" -e @secrets/secrets.yml --ask-become-pass --vault-password-file .password playbooks/sync-bird.yml

.PHONY: render-config
render-config:
	@echo "Rendering configuration files..."
	@cat .password | uv run --project=render/ --active render/render_config.py

.PHONY: render-terraform
render-terraform:
	@echo "Rendering Terraform files..."
	@cat .password | uv run --project=render/ --active render/render_terraform.py

.PHONY: render
render: render-config render-terraform

.PHONY: sync-config
sync-config: render
	@ansible-playbook -e "base_dir=$$(pwd)" -i inventory/ playbooks/sync-config.yml

.PHONY: apply
apply: sync-config
	@terraform -chdir=./terraform apply -auto-approve

.PHONY: destroy
destroy:
	@terraform -chdir=./terraform destroy -auto-approve
