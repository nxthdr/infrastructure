# `render` infrastructure and configuration files

This Python project is used to render configuration and terraform files for the infrastructure. It uses Jinja2 templates to generate the final configuration files, which are then used to deploy the infrastructure.

* `render_config.py` - Templating the configuration files
* `render_terraform.py` - Templating the terraform files


## Usage

This project uses [uv](https://docs.astral.sh/uv/) as package and project manager. Have a look at the [installtion](https://docs.astral.sh/uv/getting-started/installation/) instructions to install it locally.

As for now, this package is not meant to be used outside of this particular `infrastructure` project. In the majority of the cases, you will use the `Makefile` to run the commands. The `Makefile` is located in the root of the project. It will call the `render_config.py` and `render_terraform.py` scripts with the appropriate arguments.
