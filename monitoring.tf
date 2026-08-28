# Lightweight observability wiring, added before networking.tf was pulled
# out into its own module. legacy-networking-state/ holds a state file
# checked in by whoever set this up originally.
# data "terraform_remote_state" "networking" {
#   backend = "local"

#   config = {
#     path = "${path.module}/legacy-networking-state/terraform.tfstate"
#   }
# }

resource "aws_cloudwatch_log_group" "app" {
  name              = "/kente-retail/${terraform.workspace}/app"
  retention_in_days = 14

  tags = {
    Project     = var.project_tag
    Environment = terraform.workspace
    VpcId       = module.networking.vpc_id
  }
}
