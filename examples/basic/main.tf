# A plain HTML/CSS/JS site in ./site, served at example.com and www.example.com.
#
#   terraform init
#   terraform apply -var domain=yourdomain.com

variable "domain" {
  type = string
}

provider "aws" {
  region = "us-east-1"
}

# CloudFront certificates must live in us-east-1. Point both at us-east-1 to keep
# it simple, or set the default provider to any region you like.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "site" {
  source = "github.com/45squaredLLC/terraform-aws-static-site"

  domain   = var.domain
  site_dir = "${path.module}/site"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

output "url" {
  value = module.site.url
}

output "cloudfront_url" {
  value = module.site.cloudfront_url
}
