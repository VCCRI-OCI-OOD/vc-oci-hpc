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

first_line() {
  local output
  output="$($@)"
  printf '%s\n' "${output%%$'\n'*}"
}

printf '\nDevelopment tools installed:\n'
first_line terraform version
first_line tflint --version
oci --version
# Devcontainer image may expose ansible as ansible-community.
if command -v ansible >/dev/null 2>&1; then
  first_line ansible --version
elif command -v ansible-community >/dev/null 2>&1; then
  first_line ansible-community --version
else
  printf 'ansible: not found in PATH\n'
fi
uv --version