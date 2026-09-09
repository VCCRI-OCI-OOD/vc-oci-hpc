# OCI HPC development container

Open the repository in VS Code and run **Dev Containers: Reopen in Container**.
The environment provides:

- Terraform and TFLint
- Python 3.11, `uv`, and a project `.venv`
- OCI CLI
- Ansible and Ansible Lint
- Git and common command-line utilities
- VS Code support for Terraform, OCI, Python, Ansible, YAML, Ruff, and shell scripts

The configuration uses a published base image and Dev Container Features rather
than maintaining a project-specific Dockerfile. It does not run Docker inside
the development container. A compatible Dev Containers runtime, such as Docker
Desktop or Podman, is still required on the host.

## OCI credentials

Credentials are deliberately not copied into the image. After creating the
container, either run `oci setup config` inside it or bind-mount the host OCI
configuration by adding this property to `devcontainer.json`:

```jsonc
"mounts": [
  "source=${localEnv:USERPROFILE}/.oci,target=/home/vscode/.oci,type=bind,readonly"
]
```

Only add the mount when `%USERPROFILE%\\.oci` exists. A read-only mount works
for API-key authentication; omit `readonly` when OCI CLI commands need to update
the configuration or session tokens.

## Checks

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
tflint --recursive
ansible-lint --profile min playbooks/
ruff check .
```
