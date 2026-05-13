module "network" {
  source       = "../../modules/network"
  project_name = var.project_name
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr
}
