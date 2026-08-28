# Kente Retail — Web Tier (last sprint's Terraform)

This is the Terraform code from the Infrastructure as Code module, as it was left at
the end of last sprint: one environment, one AWS account, state on whoever's laptop
last ran `terraform apply`.

## What's here

- `main.tf` — provider and required-version configuration. No `backend` block —
  state is local (`terraform.tfstate` next to these files), which is exactly the
  problem this module's lab asks you to fix.
- `variables.tf` — the knobs this config exposes today. Nothing here is workspace-aware
  yet.
- `networking.tf` / `compute.tf` — the two pieces of infrastructure, already split into
  reusable-ish modules under `modules/`.
- `monitoring.tf` — a small CloudWatch log group, wired up before `networking.tf` was
  pulled into its own module.
- `outputs.tf` — root outputs.
- `modules/networking`, `modules/compute` — the module implementations.

## Running it (as-is, single environment)

```bash
terraform init
terraform plan
terraform apply
```

This provisions one VPC, one subnet, one security group, and one (or more) EC2
instance(s) running the Kente Retail order-service image, all in whatever AWS account
your default credentials point at.

## Your job this module

See the Learner Brief and `environment-requirements-spec.md` (in the parent
`resources/` folder) for what's actually being asked of you. In short: this code needs
to become reusable modules driven by Terraform workspaces (dev + staging, same code),
the state needs to move to a remote S3 + DynamoDB backend, and the web tier needs to be
configured end-to-end by an Ansible role fed from Terraform's outputs — no manual SSH
step left over.

Your copy of this code has one planted defect somewhere in it. Nothing about the defect
is described here — finding and explaining it is part of the assessment.


# Kente Retail — Dev/Staging Infrastructure (Terraform + Ansible)

Provisions a `dev` and `staging` environment for the Kente Retail web tier on AWS,
using Terraform (workspace-driven, remote state) for infrastructure and Ansible
(dynamic inventory, custom role, Vault-encrypted secrets) for configuration
management.

See [`ASSUMPTIONS.md`](./ASSUMPTIONS.md) for the full reasoning behind every
non-obvious decision and sandbox-driven adaptation made in this build — read that
alongside this README for the "why," not just the "how."

## Prerequisites

- Terraform >= 1.5
- AWS CLI, configured with credentials for the target sandbox account
- Ansible (`ansible-playbook`, `ansible-vault`)
- `jq`
- An existing EC2 key pair in the target region, with the matching `.pem` file
  available locally
- An S3 bucket + DynamoDB table already provisioned for remote state (see
  **Remote state backend** below — these are *not* created by this configuration)

## Project structure

```
.
├── main.tf, variables.tf, networking.tf, compute.tf, monitoring.tf, outputs.tf
├── modules/
│   ├── networking/     # security group, references to the account's existing VPC/subnet
│   └── compute/        # EC2 instances for the web tier
├── scripts/
│   └── generate_inventory.sh   # builds ansible/inventory/hosts.ini from `terraform output`
└── ansible/
    ├── ansible.cfg
    ├── playbook.yml
    ├── inventory/
    │   └── hosts.ini            # generated — do not hand-edit
    ├── group_vars/
    │   ├── dev/
    │   │   ├── vars.yml         # plaintext, safe to read/diff
    │   │   └── vault.yml        # Ansible Vault-encrypted secrets
    │   └── staging/
    │       ├── vars.yml
    │       └── vault.yml
    └── roles/
        └── webapp/
            ├── tasks/main.yml
            ├── handlers/main.yml
            ├── templates/
            │   ├── app.conf.j2   # nginx site config (non-secret)
            │   └── app.env.j2    # app environment file (holds the DB credential)
            └── defaults/main.yml
```

## Remote state backend

State lives in S3 with DynamoDB locking. The bucket and lock table must exist
*before* running `terraform init` (Terraform's S3 backend can't create the bucket
it's about to use as its own backend). Confirm with whoever provisions your sandbox
whether these already exist for you before creating your own.

```hcl
terraform {
  backend "s3" {
    bucket         = "<your-bucket-name>"
    key            = "networking/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "<your-lock-table-name>"
    encrypt        = true
  }
}
```

Each Terraform workspace's state is kept separate automatically once this backend is
configured — no manual path management needed per environment.

## Running Terraform

```bash
terraform init

terraform workspace new dev        # first time only
terraform workspace new staging    # first time only

terraform workspace select dev
terraform plan
terraform apply

terraform workspace select staging
terraform plan
terraform apply
```

Key variables (see `variables.tf` for full list and defaults):

| Variable         | Purpose                                              |
|------------------|-------------------------------------------------------|
| `aws_region`     | Region for all resources — keep consistent everywhere |
| `key_name`       | EC2 key pair name for SSH access (used by Ansible)    |
| `project_tag`    | Value for the `Project` tag on every resource         |

CIDR and instance-count values are **not** passed as flags — they're resolved
automatically per-workspace via `locals` maps keyed on `terraform.workspace`. See
`ASSUMPTIONS.md` for why, and for the sandbox constraint that limits true
per-environment VPC isolation in this particular account.

## Generating the Ansible inventory

After `apply` succeeds for a given workspace:

```bash
terraform workspace select dev
./scripts/generate_inventory.sh

terraform workspace select staging
./scripts/generate_inventory.sh
```

This reads `terraform output -json web_public_ips` and writes/updates the matching
`[dev]` or `[staging]` section in `ansible/inventory/hosts.ini`, without disturbing
the other environment's section. Run it again any time instance IPs change (e.g.
after a `terraform apply` that replaces instances).

## Running Ansible

From inside `ansible/`:

```bash
ansible-playbook -i inventory/hosts.ini playbook.yml \
  --private-key /path/to/ansible-key-pair.pem \
  --ask-vault-pass
```

You'll be prompted for the Vault password used to encrypt `group_vars/*/vault.yml`.

> **WSL users:** if your project lives under `/mnt/c/...`, Ansible will refuse to
> load `ansible.cfg` from that path (WSL mounts it as world-writable, which Ansible
> treats as untrusted). Pass `-i inventory/hosts.ini` explicitly as shown above, and
> set `ANSIBLE_HOST_KEY_CHECKING=False` / `ANSIBLE_REMOTE_USER=ec2-user` as
> environment variables rather than relying on `ansible.cfg` — or, better, move the
> project into WSL's native filesystem (e.g. `~/projects/...`) to avoid this
> entirely.

## Managing secrets (Ansible Vault)

Each environment has its own encrypted vault file. To view or edit:

```bash
ansible-vault view group_vars/dev/vault.yml
ansible-vault edit group_vars/dev/vault.yml     # decrypts, opens $EDITOR, re-encrypts on save
```

**Never** hand-edit an encrypted vault file directly, and never commit a vault file
that isn't showing `$ANSIBLE_VAULT;1.1;AES256` ciphertext when you `cat` it.

## Verifying the result

Confirm each environment's distinct database credential actually landed on its
hosts:

```bash
ssh -i /path/to/ansible-key-pair.pem ec2-user@<dev-ip> "sudo cat /etc/kente-retail/app.env"
ssh -i /path/to/ansible-key-pair.pem ec2-user@<staging-ip> "sudo cat /etc/kente-retail/app.env"
```

Dev and staging should show different `DB_PASSWORD` values, each sourced from that
environment's own encrypted vault file.

Re-running the playbook with no changes should show every task as `ok` (not
`changed`) — confirms the role is idempotent.

## Tearing down

Sandbox spend is tracked — tear down both environments once you're done:

```bash
terraform workspace select dev
terraform destroy

terraform workspace select staging
terraform destroy
```