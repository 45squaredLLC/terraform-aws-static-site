# terraform test: plans the module against a mocked AWS provider, so it needs no
# AWS account or credentials.

mock_provider "aws" {
  mock_data "aws_route53_zone" {
    defaults = {
      zone_id = "Z0000000000TEST"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn                         = "arn:aws:s3:::static-site-test"
      bucket_regional_domain_name = "static-site-test.s3.us-east-1.amazonaws.com"
    }
  }

  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      arn            = "arn:aws:cloudfront::123456789012:distribution/ETEST"
      domain_name    = "d111111abcdef8.cloudfront.net"
      hosted_zone_id = "Z2FDTNDATAQYW2"
    }
  }

  mock_resource "aws_acm_certificate_validation" {
    defaults = {
      certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/test"
    }
  }

  mock_resource "aws_cloudfront_function" {
    defaults = {
      arn = "arn:aws:cloudfront::123456789012:function/test"
    }
  }
}

mock_provider "aws" {
  alias = "us_east_1"

  mock_resource "aws_acm_certificate_validation" {
    defaults = {
      certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/test"
    }
  }
}

variables {
  domain               = "example.com"
  site_dir             = "./tests/fixtures/plain"
  invalidate_on_change = false
}

run "apex_site_with_www" {
  command = plan

  assert {
    condition     = aws_s3_bucket.site.bucket == "static-site-example-com"
    error_message = "default bucket name should come from the domain"
  }

  assert {
    condition     = toset(aws_cloudfront_distribution.site.aliases) == toset(["example.com", "www.example.com"])
    error_message = "apex + www should both be served"
  }

  assert {
    condition     = toset(aws_acm_certificate.site.subject_alternative_names) == toset(["www.example.com"])
    error_message = "certificate should cover www"
  }

  assert {
    condition     = length(aws_route53_record.site) == 4
    error_message = "A and AAAA for apex and www"
  }

  assert {
    condition     = length(aws_s3_object.file) == 4
    error_message = "every file in site_dir should be uploaded"
  }

  assert {
    condition     = aws_s3_object.file["index.html"].content_type == "text/html; charset=utf-8"
    error_message = "HTML content type"
  }

  assert {
    condition     = aws_s3_object.file["style.css"].cache_control == "public, max-age=86400"
    error_message = "CSS is cached for a day"
  }

  assert {
    condition     = aws_s3_object.file["index.html"].cache_control == "public, max-age=300, s-maxage=300"
    error_message = "without invalidation, the edge must not hold pages for a day"
  }

  assert {
    condition     = alltrue([for e in aws_cloudfront_distribution.site.custom_error_response : e.response_page_path == "/404.html"])
    error_message = "the site's own 404.html is used when present"
  }

  assert {
    condition     = length(terraform_data.invalidate) == 0
    error_message = "invalidation is off"
  }

  assert {
    condition     = alltrue([for r in values(aws_route53_record.site) : r.allow_overwrite == false])
    error_message = "existing records must not be overwritten unless asked"
  }
}

run "spa_on_a_subdomain" {
  command = plan

  variables {
    domain               = "app.example.com"
    zone_name            = "example.com"
    include_www          = false
    spa                  = true
    site_dir             = "./tests/fixtures/spa"
    invalidate_on_change = true
  }

  assert {
    condition     = aws_cloudfront_distribution.site.aliases == toset(["app.example.com"])
    error_message = "a subdomain without www"
  }

  assert {
    condition     = length(aws_acm_certificate.site.subject_alternative_names) == 0
    error_message = "no www name on the certificate"
  }

  assert {
    condition     = length(aws_route53_record.site) == 2
    error_message = "A and AAAA for the subdomain only"
  }

  assert {
    condition     = alltrue([for e in aws_cloudfront_distribution.site.custom_error_response : e.response_page_path == "/index.html"])
    error_message = "no 404.html: fall back to the home page"
  }

  assert {
    condition     = strcontains(aws_cloudfront_function.router.code, "\"spa\":true")
    error_message = "SPA mode reaches the router"
  }

  assert {
    condition     = aws_s3_object.file["index.html"].cache_control == "public, max-age=300, s-maxage=86400"
    error_message = "with invalidation the edge can hold pages longer"
  }

  assert {
    condition     = aws_s3_object.file["assets/logo.png"].cache_control == "public, max-age=2592000"
    error_message = "images are cached for 30 days"
  }

  assert {
    condition     = length(terraform_data.invalidate) == 1
    error_message = "invalidation is on"
  }
}

run "test_first_then_go_live" {
  command = plan

  variables {
    create_dns_records = false
  }

  assert {
    condition     = length(aws_route53_record.site) == 0
    error_message = "no DNS changes until create_dns_records is true"
  }
}

run "csp_only_when_set" {
  command = plan

  variables {
    content_security_policy = "default-src 'self'"
  }

  assert {
    condition     = aws_cloudfront_response_headers_policy.site.security_headers_config[0].content_security_policy[0].content_security_policy == "default-src 'self'"
    error_message = "CSP is applied when set"
  }
}

run "site_dir_needs_index_html" {
  command = plan

  variables {
    site_dir = "./tests/fixtures/spa/assets"
  }

  expect_failures = [var.site_dir]
}
