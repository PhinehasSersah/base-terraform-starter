module "compute" {
  source = "./modules/compute"

  vpc_id            = module.networking.vpc_id
  subnet_id         = module.networking.subnet_id
  security_group_id = module.networking.security_group_id
  instance_type     = var.instance_type
  instance_count    = local.instance_count_by_env[terraform.workspace]
  name_prefix       = "kente-app-${terraform.workspace}"
  project_tag       = var.project_tag
  key_name          = var.key_name

  depends_on = [module.networking]
}
