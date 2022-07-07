# Cloudtrail resources
module "cloudtrail" {
  count                 = local.cloudtrail_deploy ? 1 : 0
  source                = "../modules/cloudtrail"
  name                  = var.name
  is_organizational     = false
  is_multi_region_trail = var.cloudtrail_is_multi_region_trail
  cloudtrail_kms_enable = var.cloudtrail_kms_enable

  tags = var.tags
}
