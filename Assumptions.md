# Assumptions and observations

- Cloudwatch log VpcId referenced a local stale path. Instead of dynamic vpc id from the networking module.(Live module dependency)
- Each environment has it own CIDR range now to avoid overlapping `vpc_cidr_by_env = {
dev = "10.0.0.0/16"
staging = "10.1.0.0/16"
}`
- S3 buckets stores state files while DynamoDB stores lock keys to prevent race conditions

## Section 1 — Both environments, same code

Both `dev` and `staging` Terraform workspaces exist simultaneously, built from the
same root module and the same `modules/networking` / `modules/compute` child
modules. All environment-specific values (CIDR, instance count, naming, tags) are
resolved via `terraform.workspace`-keyed `locals` maps rather than duplicated
resource blocks or separate `.tfvars` files, so there is exactly one copy of every
resource definition.

## Section 2 — Networking

AWS account's IAM role denies
`ec2:CreateVpc` and `ec2:DescribeVpcs` (`UnauthorizedOperation`/`AccessDeniedException`).

`modules/networking` no longer creates a VPC. It also does not create
an Internet Gateway or route table but using the account's default VPC (`172.31.0.0/16`)

All three of the account's available subnets are public with no
private subnets available at all.

## Section 3 — Compute sizing

Staging is sized up relative to dev. `instance_count`
resolves to `1` for dev and `2` for staging via a `terraform.workspace`-keyed locals
map (`instance_count_by_env`), while `instance_type` remains a single shared variable
across both.

## Section 4 — State

State is stored remotely in an S3 backend (`kente-retail-tfstate-lab-145023116067-
eu-west-1-an`), with DynamoDB-based locking (`kente-retail-tflock`, partition key
`LockID`, on-demand capacity). The bucket and lock table were provisioned manually
via the AWS Console (not by this Terraform configuration itself, to avoid the
chicken-and-egg problem of a backend that doesn't exist yet when `init` first runs).

**Region bug caught and fixed:** the original `variables.tf` default for
`aws_region` was `us-east-1`, inconsistent with the `eu-west-1` region used for the
S3 bucket, DynamoDB table, and all networking resources.

## Section 5 — Configuration (Ansible)

A dynamic inventory is generated from Terraform's own outputs
(`web_public_ips`, read via `terraform output -json` and parsed with `jq -r`), rather
than via a live AWS API query (Ansible's `aws_ec2` inventory plugin was considered,
but rejected because it requires `ec2:DescribeInstances`, and this sandbox has
already proven stingy with `Describe*`/read-level permissions elsewhere

A single custom role (`roles/webapp`) installs and configures nginx as a stand-in web
tier (no real application binary was provided as part of this assignment; the focus
of grading is the configuration-management mechanism, not a specific app). The role:
installs the package, templates an nginx site config (`app.conf.j2`, non-secret:
port + environment label), creates a dedicated `/etc/kente-retail` directory, and
templates a separate application environment file (`app.env.j2`) holding the
per-environment database credential.

Per-environment values live in `group_vars/dev/` and `group_vars/staging/`, matching
the inventory group names exactly (required for Ansible's directory-based group_vars
convention to apply the right values to the right hosts).

## Section 6 — Secrets

Ansible Vault is organized as
(`group_vars/<env>/vault.yml`), separate from a plaintext `group_vars/<env>/vars.yml`
in the same directory. The plaintext file contains only non-secret values
(`app_port`, `kente_environment`) plus one indirection line
(`db_password: "{{ vault_db_password }}"`); the encrypted vault file defines only
`vault_`-prefixed variables. This split means a reviewer can read and diff
`vars.yml` without ever needing the vault password, while the actual secret never
appears in plaintext in any file that's committed to git. Dev and staging use
different `vault_db_password` values, proven by inspecting the rendered
`/etc/kente-retail/app.env` on each environment's live hosts.

## Section 7 — Tagging

Every resource created by this configuration is tagged with
`Project = kente-retail` and `Environment = ${terraform.workspace}` (`dev` or
`staging`).
