# Controller + mgmt only Terraform template

This directory includes a minimal Terraform variable template for deploying an OCI HPC environment focused on:

- Slurm controller
- Management tooling on the controller

Template file:

- `terraform.controller-mgmt-only.tfvars.example`

## How to use

1. Copy the template to a local tfvars file:

   ```bash
   cp templates/terraform.controller-mgmt-only.tfvars.example terraform.tfvars
   ```

   On Windows PowerShell:

   ```powershell
   Copy-Item .\templates\terraform.controller-mgmt-only.tfvars.example .\terraform.tfvars
   ```

2. Edit `terraform.tfvars` and replace all `REPLACE_ME` values:
   - `tenancy_ocid`
   - `targetCompartment`
   - optional existing network OCIDs if using existing VCN mode

3. Set your SSH public key in `ssh_key`.

4. Choose networking mode:
   - **Create new VCN**: keep `use_existing_vcn = false`
   - **Use existing VCN**: set `use_existing_vcn = true` and provide:
     - `vcn_id`
     - `public_subnet_id`
     - `private_subnet_id`

5. Run Terraform:

   ```bash
   terraform init
   terraform plan -out plan.out
   terraform apply plan.out
   ```

## Identity provider options

### Option 1: Built-in OpenLDAP (default)

Keep `identity_provider = "openldap"` in tfvars. The playbooks will deploy and configure OpenLDAP on the controller.

### Option 2: External FreeIPA (recommended for multi-cluster environments)

Set in tfvars:

```hcl
identity_provider      = "freeipa"
ldap                   = false
freeipa_server         = "ipa.example.com"
freeipa_realm          = "EXAMPLE.COM"
freeipa_domain         = "example.com"
freeipa_enroll_principal = "admin"
freeipa_enroll_password  = "password"  # or use environment variable in production
freeipa_ca_cert_content  = "-----BEGIN CERTIFICATE-----..."  # optional, if CA not in system trust
```

When `identity_provider="freeipa"`:
- OpenLDAP playbook is skipped
- Ansible executes FreeIPA host enrollment on the controller
- SSSD is configured to authenticate against the FreeIPA realm
- User/group lookups use FreeIPA identity backend

## Notes

- This is a minimal deployment profile and explicitly disables non-essential components like login, monitoring, compute fleet, and optional storage integrations.
- If your tenancy/policies require additional values, Terraform will prompt during `plan`/`apply`; add those into your local `terraform.tfvars`.
