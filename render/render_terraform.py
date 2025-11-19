import sys
from pathlib import Path

import jinja2
import yaml
from ansible_vault import Vault

BASE_DIR = Path(__file__).resolve().parent.parent
INVENTORY_FILE = BASE_DIR / "inventory" / "inventory.yml"
SECRETS_FILE = BASE_DIR / "secrets" / "secrets.yml"
TEMPLATES_DIR = BASE_DIR / "templates" / "terraform"
OUTPUT_DIR = BASE_DIR / "terraform"
SPECIAL_GROUPS = ["ixp", "vlt"]
TERRAFORM_TFVARS_TEMPLATE = "terraform.tfvars.j2"
TERRAFORM_PROVIDERS_TEMPLATE = "providers.tf.j2"


def render_template(template_path, output_path, context, jinja_env):
    """Renders a single Jinja2 template."""
    try:
        template_rel_path = str(template_path.relative_to(TEMPLATES_DIR.parent))
        template = jinja_env.get_template(template_rel_path)
        rendered_content = template.render(context)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w") as f:
            f.write(rendered_content)
        print(f"  Rendered: {template_path.name} -> {output_path}")
    except jinja2.exceptions.TemplateNotFound:
        print(f"Error: Template not found for {template_rel_path}", file=sys.stderr)
    except jinja2.exceptions.UndefinedError as e:
        print(
            f"Error rendering {template_path.name} ({template_rel_path}): Undefined variable - {e}",
            file=sys.stderr,
        )
    except Exception as e:
        print(
            f"Error rendering {template_path.name} ({template_rel_path}): {e}",
            file=sys.stderr,
        )


def load_vault_secrets(password):
    """Loads and decrypts secrets from the Ansible Vault file."""
    if not SECRETS_FILE.exists():
        print(
            f"Warning: Secrets file not found at {SECRETS_FILE}. Proceeding without secrets.",
            file=sys.stderr,
        )
        return {}
    try:
        vault = Vault(password.strip())
        with open(SECRETS_FILE, "rb") as f:
            decrypted_data = vault.load(f.read())
        return decrypted_data if isinstance(decrypted_data, dict) else {}
    except Exception as e:
        print(
            f"Error decrypting or loading secrets from {SECRETS_FILE}: {e}",
            file=sys.stderr,
        )
        print(
            "Please ensure the vault password is correct and the file is a valid Ansible Vault.",
            file=sys.stderr,
        )
        sys.exit(1)


def main():
    vault_password = sys.stdin.readline().strip()
    if not vault_password:
        print("Error: No vault password provided.", file=sys.stderr)
        sys.exit(1)

    try:
        with open(INVENTORY_FILE, "r") as f:
            inventory = yaml.safe_load(f)
        if not inventory:
            print(
                f"Error: Inventory file {INVENTORY_FILE} is empty or invalid.",
                file=sys.stderr,
            )
            sys.exit(1)
    except FileNotFoundError:
        print(f"Error: Inventory file not found at {INVENTORY_FILE}", file=sys.stderr)
        sys.exit(1)
    except yaml.YAMLError as e:
        print(f"Error parsing inventory file {INVENTORY_FILE}: {e}", file=sys.stderr)
        sys.exit(1)

    secrets = load_vault_secrets(vault_password)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Ensured Terraform output directory exists: {OUTPUT_DIR}")

    jinja_env = jinja2.Environment(
        loader=jinja2.FileSystemLoader(str(TEMPLATES_DIR.parent)),
        trim_blocks=True,
        lstrip_blocks=True,
        undefined=jinja2.StrictUndefined,
    )

    # Render providers.tf
    print(f"Processing template: {TERRAFORM_PROVIDERS_TEMPLATE}")
    providers_template_path = TEMPLATES_DIR / TERRAFORM_PROVIDERS_TEMPLATE
    providers_output_path = OUTPUT_DIR / "providers.tf"
    if providers_template_path.is_file():
        render_template(
            providers_template_path,
            providers_output_path,
            {"inventory": inventory},
            jinja_env,
        )
    else:
        print(
            f"  Warning: providers template {providers_template_path} not found.",
            file=sys.stderr,
        )

    # Render terraform.tfvars
    print(f"Processing template: {TERRAFORM_TFVARS_TEMPLATE}")
    tfvars_template_path = TEMPLATES_DIR / TERRAFORM_TFVARS_TEMPLATE
    tfvars_output_path = OUTPUT_DIR / "terraform.tfvars"
    if tfvars_template_path.is_file():
        render_template(
            tfvars_template_path,
            tfvars_output_path,
            secrets,
            jinja_env,
        )
    else:
        print(
            f"  Warning: terraform.tfvars template {tfvars_template_path} not found.",
            file=sys.stderr,
        )

    # Render vlt-infrastructure.tf
    print("Processing template: vlt-infrastructure.tf.j2")
    vlt_infra_template_path = TEMPLATES_DIR / "vlt-infrastructure.tf.j2"
    vlt_infra_output_path = OUTPUT_DIR / "vlt-infrastructure.tf"
    if vlt_infra_template_path.is_file():
        render_template(
            vlt_infra_template_path,
            vlt_infra_output_path,
            {"inventory": inventory},
            jinja_env,
        )
    else:
        print(
            f"  Warning: vlt-infrastructure template {vlt_infra_template_path} not found.",
            file=sys.stderr,
        )

    # Process Terraform Host Templates for SPECIAL_GROUPS
    print("Processing Terraform host files for ixp/vlt groups")
    for group_name, group_data in inventory.items():
        if group_name not in SPECIAL_GROUPS:
            continue

        print(f"Processing group: {group_name}")
        group_vars = group_data.get("vars", {})
        hosts = group_data.get("hosts", {})

        if not hosts:
            print(
                f"  Warning: Group '{group_name}' has no hosts defined. Skipping.",
                file=sys.stderr,
            )
            continue

        template_path = TEMPLATES_DIR / f"{group_name}.tf.j2"

        if not template_path.is_file():
            print(
                f"  Warning: Template file not found for group '{group_name}' at {template_path}. Skipping group.",
                file=sys.stderr,
            )
            continue

        for host_name, host_data in hosts.items():
            print(f"- Processing host: {host_name}")
            output_path = OUTPUT_DIR / f"{host_name}.tf"

            context = group_vars.copy()
            if isinstance(host_data, dict):
                context.update(host_data)
            context.update(secrets)
            context["inventory_hostname"] = host_name

            render_template(
                template_path,
                output_path,
                context,
                jinja_env,
            )

    print("Terraform rendering finished.")


if __name__ == "__main__":
    main()
