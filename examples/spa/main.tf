# A React/Vite (or Vue, Svelte, Lovable, Bolt) app on a subdomain.
#
#   npm run build            # in your app: writes dist/
#   terraform init
#   terraform apply -var domain=app.yourdomain.com -var zone_name=yourdomain.com -var site_dir=../my-app/dist

variable "domain" {
  type = string
}

variable "zone_name" {
  type = string
}

variable "site_dir" {
  type = string
}

provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "app" {
  source = "github.com/45squaredLLC/terraform-aws-static-site"

  domain      = var.domain
  zone_name   = var.zone_name
  include_www = false
  site_dir    = var.site_dir
  spa         = true

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

output "url" {
  value = module.app.url
}
