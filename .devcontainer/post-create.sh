#!/usr/bin/env bash

set -euo pipefail

workspace_root="$(git rev-parse --show-toplevel)"
cd "${workspace_root}"

uv venv --allow-existing .venv
uv pip install \
  --python .venv/bin/python \
  --editable ./mgmt \
  --requirement function/requirements.txt \
  --requirement scripts/collect_metadata/requirements.txt

printf '\nDevelopment tools installed:\n'
terraform version | head -n 1
tflint --version | head -n 1
oci --version
ansible --version | head -n 1
uv --version