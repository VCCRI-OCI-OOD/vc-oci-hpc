# Identity Provider Runbook (FreeIPA / OpenLDAP)

How to select, deploy, and migrate the cluster identity backend.

## Overview

Every node in the cluster (controller, backup, login, compute, OOD) configures exactly one identity client, selected by the `identity_provider` Terraform variable:

| `identity_provider` | Controller-side roles | Node-side client role |
| --- | --- | --- |
| `freeipa` (default) | none (uses an external IPA server) | `freeipa-client` |
| `openldap` | `ssl`, `openldap`, `cluster-cli`, `fix_ldap` | `sssd` |

The client selection is centralised in [tasks/identity_client.yml](/playbooks/tasks/identity_client.yml), which every node playbook imports:

```yaml
- name: Configure the identity client
  ansible.builtin.import_tasks: tasks/identity_client.yml
```

Imported by [site.yml](/playbooks/site.yml) (controller and backup), [compute.yml](/playbooks/compute.yml), [login.yml](/playbooks/login.yml), and [ood.yml](/playbooks/ood.yml).

Two convenience flags are defined in [group_vars/all.yml](/playbooks/group_vars/all.yml) and drive every conditional, so no playbook repeats the provider comparison:

```yaml
identity_freeipa_enabled: "{{ identity_provider == 'freeipa' }}"
identity_openldap_enabled: "{{ identity_provider == 'openldap' and (ldap | default(true) | bool) }}"
```

> [!IMPORTANT]
> The default is `freeipa`. If you want the built-in OpenLDAP server, you must set `identity_provider = "openldap"` explicitly in your `tfvars`.

## Configuration

### Option A — FreeIPA (default)

Join an existing FreeIPA realm. The cluster runs no directory server of its own.

```hcl
identity_provider        = "freeipa"
freeipa_server           = "ipa.example.com"
freeipa_realm            = "EXAMPLE.COM"
freeipa_domain           = "example.com"
freeipa_enroll_principal = "admin"
freeipa_enroll_password  = "..."   # prefer TF_VAR_freeipa_enroll_password
freeipa_ca_cert_content  = ""      # optional, only if the CA is not in the system trust store
```

Supply the password out of band rather than committing it:

```bash
export TF_VAR_freeipa_enroll_password="$(pass show freeipa/enroll)"
```

### Option B — OpenLDAP

```hcl
identity_provider = "openldap"
ldap              = true
```

### Prerequisites for FreeIPA

- Forward and reverse DNS resolution of `freeipa_server` from every node subnet.
- Outbound access from the private and controller subnets to the IPA server on TCP 389/636 (LDAP/LDAPS), TCP/UDP 88 and 464 (Kerberos), and TCP 443 if you use the IPA web API. Add the rules to the relevant security list or NSG.
- An enrollment principal with host-add permission, or a per-host one-time password.

## How the values reach the nodes

`identity_provider` and the `freeipa_*` values are rendered into the Ansible inventory by [inventory.tpl](/inventory.tpl) from the `templatefile()` calls in [controller.tf](/controller.tf) and [slurm_ha.tf](/slurm_ha.tf), and land in `/config/playbooks/inventory` on the controller. Because `/config` is the shared FSS mount, autoscaled compute and login nodes read the same values when `bin/compute.sh` and `bin/login.sh` run their playbooks.

`freeipa_ca_cert_content` is deliberately **not** passed through the inventory: an INI-format inventory cannot hold a multi-line PEM. Set it in `/config/playbooks/group_vars/all.yml` instead.

## Verification

On any node after configuration:

```bash
systemctl status sssd
id <directory-user>          # resolves UID/GID from the directory
getent passwd <directory-user>
```

FreeIPA only:

```bash
klist -k /etc/krb5.keytab | head       # host keytab present
kinit <user> && klist                  # Kerberos ticket
ipa host-show "$(hostname -f)"         # host object exists in the realm
sudo tail -f /var/log/sssd/sssd.log
```

## Applying the change to an already-deployed cluster

Terraform pushes `/config/playbooks` and the inventory only from `null_resource.controller` (triggered by the controller instance ID) and `null_resource.cluster` (no triggers). A plain `terraform apply` therefore will **not** update a running cluster.

### Manual rollout (no downtime, recommended)

1. Sync the playbook changes to the controller. `/config` is shared, so this reaches every node:

   ```bash
   rsync -av playbooks/tasks/identity_client.yml <admin>@<controller>:/config/playbooks/tasks/
   rsync -av playbooks/group_vars/all.yml        <admin>@<controller>:/config/playbooks/group_vars/
   rsync -av playbooks/{site,compute,login,ood}.yml <admin>@<controller>:/config/playbooks/
   ```

2. Add the identity variables under `[all:vars]` in **all three** inventory copies — `/config/playbooks/inventory`, `/config/playbooks/inventory_<cluster_name>`, and `/etc/ansible/hosts`:

   ```ini
   identity_provider=freeipa
   freeipa_server=ipa.example.com
   freeipa_realm=EXAMPLE.COM
   freeipa_domain=example.com
   freeipa_enroll_principal=admin
   freeipa_enroll_password='<password>'
   ```

3. Roll out only the identity step instead of re-running the full `site.yml`:

   ```bash
   cat > /config/playbooks/identity_rollout.yml <<'EOF'
   - hosts: controller, slurm_backup, compute, login
     become: true
     tasks:
       - ansible.builtin.import_tasks: tasks/identity_client.yml
   EOF

   ansible-playbook -i /etc/ansible/hosts /config/playbooks/identity_rollout.yml --check --diff
   ansible-playbook -i /etc/ansible/hosts /config/playbooks/identity_rollout.yml --limit <one-test-node>
   ```

   Verify on the test node, then re-run without `--limit`.

4. Update your `tfvars` to match, so newly provisioned nodes are consistent.

### Terraform-driven rollout (disruptive)

```bash
terraform apply -replace=null_resource.controller -replace=null_resource.cluster
```

This re-copies the playbooks, regenerates the inventory, and re-runs `configure.sh` (full `site.yml`) across the cluster. Use a maintenance window.

## Migrating OpenLDAP to FreeIPA

- **UID/GID drift is the main hazard.** FreeIPA users will generally have different UIDs and GIDs than the cluster OpenLDAP directory. Home directories on `/home` (NFS or FSS) and any user-owned scratch data will need a `chown` pass, and Slurm accounting associations should be re-checked with `sacctmgr show assoc`. Assigning matching IDs in IPA before cutover avoids this entirely.
- **Retire the old directory.** Switching the variable stops the `openldap` role from running, but an already-installed `slapd` keeps serving on the controller. Stop and disable it only after FreeIPA lookups are confirmed working on every node.
- **Cluster CLI**: the `cluster-cli` user-management commands are OpenLDAP-specific and are skipped under FreeIPA. Manage users with `ipa user-add` and friends instead.

## Troubleshooting

| Symptom | Likely cause | Action |
| --- | --- | --- |
| `ipa-client-install` fails with "Cannot connect" | DNS or firewall to the IPA server | Check `dig <freeipa_server>`, security list/NSG rules for 389/636/88/464 |
| Enrollment fails on credentials | Principal lacks host-add permission, or wrong password | Verify the principal in IPA; check `/var/log/ipaclient-install.log` |
| Users resolve on the controller but not on compute | Inventory not updated on the shared copies, or node built before the change | Re-run the identity rollout playbook against that node |
| `id <user>` empty, SSSD running | Cached negative lookup or CA mismatch | `sudo sss_cache -E && sudo systemctl restart sssd`, then check `/var/log/sssd/sssd.log` |
| Jobs fail to launch after the switch | `slurmd` starts before SSSD | `slurmd.service` already orders `After=sssd.service`; confirm SSSD is enabled on the node |

## Security notes

- `freeipa_enroll_password` is rendered into `/config/playbooks/inventory` in plaintext, following the same pattern as existing bucket credentials. Restrict the file mode, and prefer a per-host one-time password over a reusable admin password.
- Mark the variable as sensitive in any wrapper automation and never commit it to `tfvars` in source control.
