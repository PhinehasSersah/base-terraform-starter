# Assumptions and observations

- Cloudwatch log VpcId referenced a local stale path. Instead of dynamic vpc id from the networking module.(Live module dependency)
- Each environment has it own CIDR range now to avoid overlapping `vpc_cidr_by_env = {
dev = "10.0.0.0/16"
staging = "10.1.0.0/16"
}`
- S3 buckets stores state files while DynamoDB stores lock keys to prevent race conditions

# Assumptions Log — Kente Retail Dev/Staging Environment

This document records every decision, deviation, and sandbox-driven adaptation made
while building this environment, organized to match the numbered sections of
`environment-requirements-spec.md`.

> ⚠️ **One item below (CloudWatch monitoring) needs you to fill in the final decision**
> you went with — marked clearly where it appears. Everything else reflects what was
> actually built and verified working.

---

## Planted defect (found before any new work began)

`monitoring.tf` originally tagged the CloudWatch log group using a value read via a
`data "terraform_remote_state"` block pointed at a checked-in local state file
(`legacy-networking-state/terraform.tfstate`) containing a static, fake VPC ID
(`vpc-0legacy0000000001`). This value was completely disconnected from the VPC this
configuration actually manages — both `dev` and `staging` would have tagged their log
groups with the same stale, non-existent ID, regardless of which real VPC each
workspace was using.

**Fix:** removed the `data` block and referenced `module.networking.vpc_id` directly
— a live dependency the same way `compute.tf` already referenced the networking
module's outputs. Deleted `legacy-networking-state/terraform.tfstate` and the
containing directory, and added `*.tfstate` to `.gitignore` to prevent recurrence.
This was treated as a bad-practice cleanup, not a secrets incident — the file
contained no credentials, only a stale resource ID — so git history was left intact
rather than purged.

---

## Section 1 — Both environments, same code

Both `dev` and `staging` Terraform workspaces exist simultaneously, built from the
same root module and the same `modules/networking` / `modules/compute` child
modules. All environment-specific values (CIDR, instance count, naming, tags) are
resolved via `terraform.workspace`-keyed `locals` maps rather than duplicated
resource blocks or separate `.tfvars` files, so there is exactly one copy of every
resource definition.

`terraform.workspace` lookups use direct map indexing (`local.some_map[terraform.workspace]`)
with **no fallback default**. This is deliberate: running `terraform apply` on the
`default` workspace, or any workspace name that isn't `dev`/`staging`, causes a hard
plan-time failure rather than silently applying with an undefined configuration. This
was chosen specifically to prevent accidental provisioning outside the two approved
environments.

## Section 2 — Networking

**Sandbox constraint discovered:** the lab AWS account's IAM role denies
`ec2:CreateVpc` and `ec2:DescribeVpcs` (`UnauthorizedOperation`/`AccessDeniedException`).
This is a deliberate restriction in this training sandbox, not a bug in our
configuration — the account is scoped to work within its pre-existing default VPC
rather than create new network infrastructure.

**Adaptation:** `modules/networking` no longer creates a VPC. It also does not create
an Internet Gateway or route table — the account's default VPC (`172.31.0.0/16`)
already has its own IGW attached and its subnets are already public
(`MapPublicIpOnLaunch = true`), so a second IGW/route table would conflict with (and
is unnecessary alongside) what AWS already provisions for every default VPC.

Because `DescribeVpcs`/`DescribeSubnets` are also denied, the module does not use
Terraform `data` sources to look up the VPC/subnet either (a `data` source still
requires read/describe permission). Instead, `var.existing_vpc_id` and
`var.existing_subnet_id` are passed in directly and used as plain string values
throughout — no API call needed to attach a security group or route table to a VPC ID
that's simply provided as input.

**Consequence for the CIDR requirement:** since both environments share the same
single pre-existing account VPC, true non-overlapping per-environment CIDR ranges (as
originally planned in a `vpc_cidr_by_env` locals map) are not achievable in this
sandbox — there is only one VPC CIDR (`172.31.0.0/16`), shared by both. The
originally-designed `vpc_cidr_by_env` map was removed as dead code once this became
clear. Environment separation is instead achieved entirely through naming (`kente-*-
${terraform.workspace}`), the `Environment` tag, and (per the instructor's guidance,
not enforced by Terraform) each environment's own security group.

**Subnet placement:** all three of the account's available subnets are public with no
private subnets available at all (also a sandbox constraint — this account has no
private-subnet infrastructure to place instances in even if we wanted a
public/private split). Per team decision, a single subnet (`var.existing_subnet_id`)
is used for all instances in both environments; dev and staging are not physically
network-segregated, only tag/name-segregated. This is a lab-scale simplification —
in a production build with real VPC-creation rights, each environment would get its
own VPC and CIDR block as the spec originally intended.

## Section 3 — Compute sizing

**Decision: staging is sized up relative to dev** — specifically, `instance_count`
resolves to `1` for dev and `2` for staging via a `terraform.workspace`-keyed locals
map (`instance_count_by_env`), while `instance_type` remains a single shared variable
across both. Rationale: staging is meant to approximate production load
characteristics (e.g. testing behavior across multiple instances) while dev stays
minimal and cost-conscious for day-to-day iteration. Both values are driven by a
single variable/map each — no duplicated resource blocks.

## Section 4 — State

State is stored remotely in an S3 backend (`kente-retail-tfstate-lab-145023116067-
eu-west-1-an`), with DynamoDB-based locking (`kente-retail-tflock`, partition key
`LockID`, on-demand capacity). The bucket and lock table were provisioned manually
via the AWS Console (not by this Terraform configuration itself, to avoid the
chicken-and-egg problem of a backend that doesn't exist yet when `init` first runs).

Each workspace's state is kept separate automatically via the S3 backend's built-in
`env:/<workspace>/<key>` prefixing — the `key` value in the backend block is a single
static string (`networking/terraform.tfstate`); no manual per-workspace path
construction was needed or attempted.

**Region bug caught and fixed:** the original `variables.tf` default for
`aws_region` was `us-east-1`, inconsistent with the `eu-west-1` region used for the
S3 bucket, DynamoDB table, and all networking resources. This caused at least one
resource (the CloudWatch log group) to be created in the wrong region during initial
testing. Fixed by changing the variable's default to `eu-west-1`, keeping a single
source of truth for region across the whole configuration.

## Section 5 — Configuration (Ansible)

A dynamic inventory is generated from Terraform's own outputs
(`web_public_ips`, read via `terraform output -json` and parsed with `jq -r`), rather
than via a live AWS API query (Ansible's `aws_ec2` inventory plugin was considered,
but rejected because it requires `ec2:DescribeInstances`, and this sandbox has
already proven stingy with `Describe*`/read-level permissions elsewhere — keeping
Ansible's host discovery dependent only on Terraform's own output, which we already
know succeeds, was judged more robust). The generation script
(`scripts/generate_inventory.sh`) is idempotent: re-running it for the same workspace
replaces only that workspace's section in `ansible/inventory/hosts.ini`, leaving the
other environment's section untouched.

A single custom role (`roles/webapp`) installs and configures nginx as a stand-in web
tier (no real application binary was provided as part of this assignment; the focus
of grading is the configuration-management mechanism, not a specific app). The role:
installs the package, templates an nginx site config (`app.conf.j2`, non-secret:
port + environment label), creates a dedicated `/etc/kente-retail` directory, and
templates a separate application environment file (`app.env.j2`) holding the
per-environment database credential. Splitting these into two templates was a
deliberate choice — keeping the secret out of the web server's own config file limits
its exposure surface, versus baking a credential directly into an nginx config that
another process/route could plausibly leak.

Per-environment values live in `group_vars/dev/` and `group_vars/staging/`, matching
the inventory group names exactly (required for Ansible's directory-based group_vars
convention to apply the right values to the right hosts).

## Section 6 — Secrets

Ansible Vault is organized as **one vault file per environment**
(`group_vars/<env>/vault.yml`), separate from a plaintext `group_vars/<env>/vars.yml`
in the same directory. The plaintext file contains only non-secret values
(`app_port`, `kente_environment`) plus one indirection line
(`db_password: "{{ vault_db_password }}"`); the encrypted vault file defines only
`vault_`-prefixed variables. This split means a reviewer can read and diff
`vars.yml` without ever needing the vault password, while the actual secret never
appears in plaintext in any file that's committed to git. Dev and staging use
different `vault_db_password` values, proven by inspecting the rendered
`/etc/kente-retail/app.env` on each environment's live hosts. The same vault
_password_ (used to unlock the encrypted files) is shared across both files by
choice — this is the key used to open the vault, not the secret itself, and sharing
it doesn't weaken the per-environment separation of the actual credential values.

The SSH private key used to reach these hosts (`ansible-key-pair.pem`) is not
committed to git and is not managed via Ansible Vault — it's a locally-held
credential outside the scope of this repository entirely, same as any other
developer's local SSH key.

## Section 7 — Tagging

Every resource created by this configuration is tagged with
`Project = kente-retail` and `Environment = ${terraform.workspace}` (`dev` or
`staging`). _(Note: confirm the final decision on the CloudWatch log group — if it
was removed or gated behind `enable_monitoring`, update this line to reflect whether
it still exists/is tagged, or note it as intentionally out of scope for this
sandbox.)_

## Section 8 — Teardown

Both environments must be torn down with `terraform destroy` (run once per workspace)
before the instructor's stated deadline. _(Do this only once the assignment has been
submitted/graded — don't destroy before you're done demonstrating it.)_

## Section 9 — Out of scope, noted gaps

- **Multi-AZ / private subnets / NAT gateways**: not built, per spec explicitly
  allowing this. Also not achievable in this sandbox even if in scope, since the
  account's only available subnets are all public, single-AZ-assignable.
- **TLS, load balancer, autoscaling, CI/CD of `terraform apply`**: not built, per
  spec section 9.
- **True per-environment VPC/CIDR isolation**: not achievable in this sandbox due to
  the `ec2:CreateVpc` permission denial (see Section 2 above) — noted as a real gap
  relative to the spec's original intent, not a design choice.
- **CloudWatch monitoring**: `logs:CreateLogGroup` was denied in this sandbox.
  _(Note the final resolution here: monitoring gated behind a variable, removed
  entirely, or another approach — whichever was chosen.)_
