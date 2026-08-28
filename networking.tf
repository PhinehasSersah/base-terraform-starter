module "networking" {
  source = "./modules/networking"

  vpc_cidr    = local.vpc_cidr_by_env[terraform.workspace]
  project_tag = var.project_tag
}
