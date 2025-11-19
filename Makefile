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

# VLT Server Automation
.PHONY: vlt-infrastructure
vlt-infrastructure:
	@echo "==> Provisioning VLT infrastructure (Vultr servers + DNS)..."
	@terraform -chdir=./terraform apply -auto-approve -target=module.vlt_server

.PHONY: vlt-setup
vlt-setup: render-config
	@echo "==> Running VLT server setup playbooks..."
	@echo "Note: You will be prompted for the root password from Vultr console."
	@echo ""
	@ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -k -i inventory/ \
		-e "base_dir=$$(pwd)" -e @secrets/secrets.yml -e 'ansible_user=root' \
		--vault-password-file .password \
		playbooks/install-user.yml --limit vlt
	@echo ""
	@echo "==> User created. Running remaining setup as nxthdr user..."
	@ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory/ \
		-e "base_dir=$$(pwd)" --ask-become-pass \
		playbooks/install-docker.yml --limit vlt
	@ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory/ \
		-e "base_dir=$$(pwd)" --become \
		playbooks/install-hsflowd.yml --limit vlt
	@ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory/ \
		-e "base_dir=$$(pwd)" --become \
		playbooks/install-rsyslog.yml --limit vlt
	@ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory/ \
		-e "base_dir=$$(pwd)" --become \
		playbooks/install-bird.yml --limit vlt
	@ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory/ \
		-e "base_dir=$$(pwd)" --become \
		playbooks/install-vlt-network.yml --limit vlt

.PHONY: vlt-config
vlt-config: render-config
	@echo "==> Syncing VLT configurations (BIRD, Docker containers)..."
	@$(MAKE) sync-bird
	@$(MAKE) apply

.PHONY: vlt
vlt: render-terraform vlt-infrastructure vlt-setup vlt-config
	@echo ""
	@echo "==> VLT server provisioning complete!"
	@echo ""
	@terraform -chdir=./terraform output vlt_servers

.PHONY: vlt-destroy
vlt-destroy:
	@echo "==> Destroying VLT server resources..."
	@echo "WARNING: This will destroy Docker containers and then the server."
	@echo "Make sure the server is still in inventory.yml before running this!"
	@echo ""
	@read -p "Enter hostname to destroy (e.g., vltfra01): " hostname; \
	if [ -z "$$hostname" ]; then \
		echo "Error: No hostname provided"; \
		exit 1; \
	fi; \
	echo "Rendering Terraform to ensure provider exists..."; \
	$(MAKE) render-terraform; \
	echo ""; \
	echo "Destroying Docker resources for $$hostname..."; \
	terraform -chdir=./terraform destroy -auto-approve -target=docker_container.$${hostname}_alloy -target=docker_container.$${hostname}_node_exporter -target=docker_container.$${hostname}_cadvisor -target=docker_container.$${hostname}_saimiris -target=docker_network.$${hostname}_backend -target=docker_image.$${hostname}_alloy -target=docker_image.$${hostname}_node_exporter -target=docker_image.$${hostname}_cadvisor -target=docker_image.$${hostname}_saimiris -target=data.docker_registry_image.$${hostname}_saimiris || true; \
	echo ""; \
	echo "Destroying Vultr server and DNS for $$hostname..."; \
	terraform -chdir=./terraform destroy -auto-approve -target=module.vlt_server[\"$$hostname\"]; \
	echo ""; \
	echo "==> Server destroyed. You can now remove $$hostname from inventory.yml"

# IXP Server Automation
.PHONY: ixp-setup
ixp-setup: render-config
	@echo "==> Running IXP server setup playbooks..."
	@echo "Note: Server must already exist and be accessible via SSH."
	@echo "Note: You will be prompted for the root password."
	@echo ""
	@ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -k -i inventory/ \
		-e "base_dir=$$(pwd)" -e @secrets/secrets.yml -e 'ansible_user=root' \
		--vault-password-file .password \
		playbooks/install-user.yml --limit ixp
	@echo ""
	@echo "==> User created. Running remaining setup as nxthdr user..."
	@ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory/ \
		-e "base_dir=$$(pwd)" --ask-become-pass \
		playbooks/install-docker.yml --limit ixp
	@ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory/ \
		-e "base_dir=$$(pwd)" --become \
		playbooks/install-hsflowd.yml --limit ixp
	@ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory/ \
		-e "base_dir=$$(pwd)" --become \
		playbooks/install-rsyslog.yml --limit ixp
	@ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory/ \
		-e "base_dir=$$(pwd)" --become \
		playbooks/install-bird.yml --limit ixp
	@ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory/ \
		-e "base_dir=$$(pwd)" --become \
		playbooks/install-wireguard.yml --limit ixp

.PHONY: ixp-config
ixp-config: render-config
	@echo "==> Syncing IXP configurations (BIRD, WireGuard, Docker containers)..."
	@$(MAKE) sync-bird
	@$(MAKE) sync-wireguard
	@$(MAKE) apply

.PHONY: ixp
ixp: ixp-setup ixp-config
	@echo ""
	@echo "==> IXP server setup complete!"

# Core Server Automation
.PHONY: core-setup
core-setup: render-config
	@echo "==> Running Core server setup playbooks..."
	@echo "Note: Server must already exist and be accessible via SSH."
	@echo "Note: You will be prompted for the root password."
	@echo ""
	@ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -k -i inventory/ \
		-e "base_dir=$$(pwd)" -e @secrets/secrets.yml -e 'ansible_user=root' \
		--vault-password-file .password \
		playbooks/install-user.yml --limit core
	@echo ""
	@echo "==> User created. Running remaining setup as nxthdr user..."
	@ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory/ \
		-e "base_dir=$$(pwd)" --ask-become-pass \
		playbooks/install-docker.yml --limit core
	@ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory/ \
		-e "base_dir=$$(pwd)" --become \
		playbooks/install-hsflowd.yml --limit core
	@ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory/ \
		-e "base_dir=$$(pwd)" --become \
		playbooks/install-rsyslog.yml --limit core
	@ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory/ \
		-e "base_dir=$$(pwd)" --become \
		playbooks/install-bird.yml --limit core
	@ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory/ \
		-e "base_dir=$$(pwd)" --become \
		playbooks/install-wireguard.yml --limit core

.PHONY: core-config
core-config: render-config
	@echo "==> Syncing Core configurations (BIRD, WireGuard, Docker containers)..."
	@$(MAKE) sync-bird
	@$(MAKE) sync-wireguard
	@$(MAKE) apply

.PHONY: core
core: core-setup core-config
	@echo ""
	@echo "==> Core server setup complete!"
