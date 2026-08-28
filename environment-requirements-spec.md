# Kente Retail — Dev/Staging Environment Requirements Spec

This is the written spec referenced in the Learner Brief: what dev and staging each
need, from the CTO's side. Build to this, and document any gap you had to fill in
yourself in your Assumptions Log.

## 1. Both environments, same code

- `dev` and `staging` must both exist **simultaneously** — this is not a "tear one
  down to build the other" exercise.
- Both must be demonstrably built from the **same** Terraform module source. If you
  find yourself maintaining two copies of a resource block that differ only in a
  value, that value belongs in a variable, not in a second copy of the resource.
- Terraform workspaces are the mechanism for this. `terraform.workspace` is available
  to reference inside any module, not just the root — use it for naming so dev and
  staging resources never collide.

## 2. Networking

- Each environment gets its own VPC. Non-overlapping CIDR ranges — pick your own
  scheme and note it in your Assumptions Log (e.g. a `/16` per environment is more
  than enough for this lab).
- One public subnet per environment is sufficient for this pass. Multi-AZ, private
  subnets, and NAT gateways are out of scope — note them as a follow-up if you spot
  the gap, you are not required to build them.
- The web tier must be reachable on its application port from the class network, and
  reachable via SSH from wherever you'll run Ansible from.

## 3. Compute sizing — deliberately not specified here

Whether dev and staging should run identical instance types/counts, or whether
staging should be sized up to more closely resemble production load, is **your call**.
Pick one, wire it through a variable (don't hardcode two different literal values in
two different places), and justify the choice in your Assumptions Log. Either answer
is acceptable if you can defend it.

## 4. State

- State must live in a remote S3 + DynamoDB backend, not on a laptop. Each workspace's
  state is naturally kept separate by Terraform once the backend is configured
  correctly — verify that dev's state and staging's state are not stepping on each
  other.
- Whoever provisions your sandbox account may already have your S3 bucket and
  DynamoDB lock table ready — check with your instructor before assuming you need to
  create them yourself.

## 5. Configuration — no manual steps

- Every server the web tier runs on must be configured entirely by Ansible, using an
  inventory generated from (or otherwise directly sourced from) Terraform's outputs.
  If you SSH in and hand-edit a config file to get something working, that step isn't
  done yet.
- At least one custom Ansible role is required. A single flat `playbook.yml` with
  inline tasks does not meet this requirement, no matter how well it works.
- dev and staging must be able to have different configuration values (at minimum: a
  distinct database credential per environment) without copy-pasting playbook logic —
  use `group_vars` / `host_vars` per environment.

## 6. Secrets

- No secret — a database password, an API key, anything a leaked `git log` would
  embarrass us over — may appear in plaintext anywhere in the repository or its
  history. This is non-negotiable; it is the direct cause of last sprint's incident.
- Ansible Vault manages any secret this configuration needs. How you organize the
  vault-encrypted file(s) (one shared vault file, one per environment, etc.) is your
  call — document the choice.

## 7. Tagging

- Tag every resource you create with `Project = kente-retail` and
  `Environment = dev` or `Environment = staging` as appropriate. This is how your
  instructor's tooling tells your dev resources apart from your staging resources
  during grading — untagged or mistagged resources may be graded as if they don't
  exist.

## 8. Teardown

- Sandbox spend is being tracked. Tear down both environments (`terraform destroy` in
  each workspace) by the deadline your instructor gives this cohort. Leaving either
  environment running past that date is treated as an incident, not a lab submission
  detail.

## 9. Out of scope for this pass

TLS/certificate management, autoscaling, a load balancer in front of the web tier, and
CI/CD automation of the `terraform apply` itself are not assessed in this lab. If you
notice a gap in one of these, note it in your Assumptions Log — you are not required to
build it.
