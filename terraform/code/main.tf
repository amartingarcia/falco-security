# Resource Group
module "resource_group" {
  source = "../modules/resource-group"
  name   = var.name
  tags   = var.tags
}
