# FreeIPA Integration Guide

This implementation adds support for integrating with **external FreeIPA** identity providers as an alternative to the built-in OpenLDAP deployment.

## Overview

The Terraform/Ansible stack now supports two identity provider modes:

1. **OpenLDAP (default)**: Deploy and configure OpenLDAP on the Slurm controller
2. **FreeIPA (external)**: Join an existing FreeIPA realm and configure SSSD for centralized identity/auth

## Architecture

```
FreeIPA Server                    Slurm Controller
  (IPA, KDC)  <---LDAP/Kerberos---> (ipa-client, SSSD)
   (ca.crt)   <---TLS/CA Auth------> (/etc/ipa/ca.crt)
```

## Configuration

### Step 1: Set Terraform variables

In `terraform.tfvars`:

```hcl
identity_provider        = "freeipa"
ldap                     = false
freeipa_server           = "ipa.example.com"
freeipa_realm            = "EXAMPLE.COM"
freeipa_domain           = "example.com"
freeipa_enroll_principal = "admin"
freeipa_enroll_password  = "password"  # Use secrets manager in production
freeipa_ca_cert_content  = ""  # Optional; leave empty if CA is in system trust
```

### Step 2: Provide FreeIPA credentials securely

**Option A: Environment variable (development)**
```bash
export TF_VAR_freeipa_enroll_password="$(pass show freeipa/admin)"
terraform plan
```

**Option B: Vault/Secrets Manager (production)**
Use OCI Vault or your secrets manager to inject credentials at apply time:
```bash
oci secrets secret get-secret-value --secret-id "freeipa-password" --query data.secretBundleContent.content --raw-output | base64 -d
```

### Step 3: Run Terraform + Ansible

```bash
terraform init
terraform plan -out plan.out
terraform apply plan.out
```

The Ansible playbooks will:
1. Skip OpenLDAP setup (because `ldap=false`)
2. Install FreeIPA client packages
3. Enroll the controller host in the FreeIPA realm
4. Configure SSSD for identity lookups
5. Restart SSSD to apply configuration

## Validation

After deployment, verify FreeIPA enrollment:

```bash
# SSH to controller
ssh opc@<controller-ip>

# Verify realm enrollment
realm list
# Output should show EXAMPLE.COM realm with 'configured: yes'

# Test user lookup from FreeIPA
id someuser@EXAMPLE.COM
# Output should show user UID/GID from FreeIPA

# Check SSSD service status
sudo systemctl status sssd
# Output should show 'active (running)'

# Check SSSD logs for errors
sudo tail -f /var/log/sssd/sssd.log
```

## SSSD Configuration

After enrollment, SSSD is automatically configured to:

- **Domain**: Uses FreeIPA domain (e.g., `example.com`)
- **Provider**: IPA backend for identity/auth/access
- **Kerberos**: Automatic for password auth if FreeIPA KDC is reachable
- **Fallback**: Falls back to LDAP if Kerberos is unavailable

SSSD config location: `/etc/sssd/sssd.conf`

## Sudoers and Access Control

If you use FreeIPA's sudo rules:

1. Define sudo rules in FreeIPA Web UI or CLI:
   ```bash
   ipa sudorule-add allow-slurm-admin
   ipa sudorule-add-host allow-slurm-admin --hosts slurm-controller
   ipa sudorule-add-user allow-slurm-admin --users admins
   ipa sudorule-add-runasuser allow-slurm-admin --users root
   ```

2. Slurm controller will auto-fetch rules via SSSD

3. Local sudoers file is still available for emergency access

## Troubleshooting

### Enrollment fails: "Server not found"

**Cause**: Controller cannot resolve FreeIPA server hostname or reach it over LDAP/Kerberos ports

**Solution**:
- Verify DNS resolution: `nslookup ipa.example.com`
- Check network/firewall rules allow LDAP (389/636) and Kerberos (88/464) traffic
- Verify `freeipa_server` variable matches DNS CNAME/A record for IPA server

### Enrollment fails: "Invalid credentials"

**Cause**: Principal or password is incorrect

**Solution**:
- Verify `freeipa_enroll_principal` exists in FreeIPA with enrollment permissions
- Verify password is correct
- Check FreeIPA logs: `ipa-server-log | grep -i error`

### SSSD cannot authenticate users

**Cause**: CA certificate mismatch or SSSD misconfiguration

**Solution**:
- If using custom CA, ensure `freeipa_ca_cert_content` PEM matches FreeIPA server's CA
- Restart SSSD: `sudo systemctl restart sssd`
- Check SSSD logs: `sudo journalctl -u sssd -n 50`

### Users cannot login

**Cause**: User not in FreeIPA or HBAC rule blocks access

**Solution**:
- Verify user exists in FreeIPA: `ipa user-find someuser`
- Check HBAC rules allow user on this host: `ipa hbacrule-find`
- If HBAC is not configured, all users are allowed by default

## Reverting to OpenLDAP

If you need to revert to built-in OpenLDAP:

1. Update Terraform vars:
   ```hcl
   identity_provider = "openldap"
   ldap              = true
   ```

2. Unenroll from FreeIPA (on controller):
   ```bash
   sudo ipa-client-install --uninstall --unattended
   ```

3. Re-run Ansible to deploy OpenLDAP:
   ```bash
   ansible-playbook site.yml -i inventory
   ```

## Production Best Practices

1. **Never commit passwords**: Use OCI Vault or Terraform variables with environment variable injection
2. **Use TLS for FreeIPA server**: Ensure `ipa.example.com` is HTTPS/TLS
3. **Provide CA certificate**: Set `freeipa_ca_cert_content` if your CA is not in system trust stores
4. **Monitor enrollment**: Check SSSD logs after Terraform apply for any silent failures
5. **Backup enrollment credentials**: Store `freeipa_enroll_principal` password securely for re-enrollment
6. **Test HBAC before production**: Configure FreeIPA HBAC rules to restrict access per host/service

## File Locations

On controller after FreeIPA enrollment:

```
/etc/ipa/               # FreeIPA client configuration
/etc/ipa/ca.crt         # FreeIPA CA certificate
/etc/sssd/sssd.conf     # SSSD configuration (auto-generated by enrollment)
/var/log/sssd/          # SSSD logs for debugging
/var/lib/ipa/           # IPA client cache/state
```

## Related Documentation

- FreeIPA Documentation: https://freeipa.readthedocs.io/
- SSSD Documentation: https://sssd.io/
- OCI Vault Integration: See `.../documentation/Prerequisites.md`
