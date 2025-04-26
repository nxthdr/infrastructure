import os  # Import the os module
import shutil
import stat  # Import stat for more readable permission setting
import sys
from pathlib import Path

import jinja2
import yaml
from ansible_vault import Vault

BASE_DIR = Path(__file__).resolve().parent.parent
INVENTORY_FILE = BASE_DIR / "inventory" / "inventory.yml"
SECRETS_FILE = BASE_DIR / "secrets" / "secrets.yml"
TEMPLATES_DIR = BASE_DIR / "templates/config"
OUTPUT_DIR = BASE_DIR / ".rendered"
SPECIAL_GROUPS = ["ixp", "vlt"]


def set_executable(file_path):
    """Sets executable permission (+x) for the owner and group, read for others."""
    try:
        # Get current permissions
        current_stat = os.stat(file_path)
        # Add owner and group execute bits (u+x, g+x)
        # Keep existing read/write bits, ensure others have read (o+r)
        # 0o755 is a common setting (rwxr-xr-x)
        os.chmod(
            file_path, current_stat.st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IROTH
        )
        # Alternative simpler: os.chmod(file_path, 0o755) # Sets rwxr-xr-x directly
        print(f"    Set executable: {file_path}")
    except Exception as e:
        print(f"    Error setting executable bit for {file_path}: {e}", file=sys.stderr)


def render_template(template_path, output_path, context, jinja_env, base_template_dir):
    try:
        template_rel_path = str(template_path.relative_to(base_template_dir))
        template = jinja_env.get_template(template_rel_path)
        rendered_content = template.render(context)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w") as f:
            f.write(rendered_content)
        print(f"  Rendered: {template_path.name} -> {output_path}")
        if output_path.suffix == ".sh":
            set_executable(output_path)
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


def copy_file(source_path, output_path):
    try:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_path, output_path)
        if output_path.suffix == ".sh":
            set_executable(output_path)
    except Exception as e:
        print(
            f"Error copying {source_path.name} to {output_path}: {e}", file=sys.stderr
        )


def process_host_files(
    host_name, input_dir, host_data, group_vars, secrets, jinja_env, base_template_dir
):
    host_output_dir = OUTPUT_DIR / host_name
    print(f"- Processing host: {host_name} -> {host_output_dir}")
    host_output_dir.mkdir(exist_ok=True)

    context = group_vars.copy()
    if isinstance(host_data, dict):
        context.update(host_data)
    context.update(secrets)
    context["inventory_hostname"] = host_name

    if not input_dir.is_dir():
        print(
            f"  Warning: Input directory not found: {input_dir}. Skipping files for {host_name}.",
            file=sys.stderr,
        )
        return

    for item_path in input_dir.rglob("*"):
        if item_path.is_file():
            relative_path = item_path.relative_to(input_dir)
            output_path = host_output_dir / relative_path

            if item_path.suffix == ".j2":
                template_output_path = output_path.with_suffix("")
                render_template(
                    item_path,
                    template_output_path,
                    context,
                    jinja_env,
                    base_template_dir,
                )
            else:
                copy_file(item_path, output_path)


def load_vault_secrets(password):
    """Loads and decrypts secrets from the Ansible Vault file."""
    if not SECRETS_FILE.exists():
        print(
            f"Warning: Secrets file not found at {SECRETS_FILE}. Proceeding without secrets.",
            file=sys.stderr,
        )
        return {}
    try:
        # Strip potential newline from password read from stdin/file
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
    # Read password from standard input
    print("Reading vault password from stdin...", file=sys.stderr)  # Info message
    vault_password = sys.stdin.readline().strip()
    if not vault_password:
        print("Error: No vault password received via stdin.", file=sys.stderr)
        sys.exit(1)

    # Parse the inventory file
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

    # Prepare output directory for config files
    if OUTPUT_DIR.exists():
        print(f"Clearing existing config output directory: {OUTPUT_DIR}")
        shutil.rmtree(OUTPUT_DIR)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Created config output directory: {OUTPUT_DIR}")

    # Set up Jinja2 environment for config templates
    jinja_env = jinja2.Environment(
        loader=jinja2.FileSystemLoader(str(TEMPLATES_DIR)),
        trim_blocks=True,
        lstrip_blocks=True,
        undefined=jinja2.StrictUndefined,
    )

    # Process Host-Specific Config Templates
    print("Processing host-specific config templates...")
    for group_name, group_data in inventory.items():
        print(f"Processing group: {group_name}")
        group_vars = group_data.get("vars", {})
        hosts = group_data.get("hosts", {})

        if not hosts:
            print(
                f"  Warning: Group '{group_name}' has no hosts defined. Skipping.",
                file=sys.stderr,
            )
            continue

        for host_name, host_data in hosts.items():
            if group_name in SPECIAL_GROUPS:
                input_template_dir = TEMPLATES_DIR / group_name
            else:
                input_template_dir = TEMPLATES_DIR / group_name / host_name

            process_host_files(
                host_name,
                input_template_dir,
                host_data,
                group_vars,
                secrets,
                jinja_env,
                TEMPLATES_DIR,
            )

    print("Config templating process finished.")


if __name__ == "__main__":
    main()
