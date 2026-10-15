output "url" {
  description = "The site's address."
  value       = "https://${var.domain}"
}

output "cloudfront_url" {
  description = "Test address: the site answers here as soon as the apply finishes, before DNS points at it."
  value       = "https://${aws_cloudfront_distribution.site.domain_name}"
}

output "distribution_id" {
  description = "CloudFront distribution ID (for manual cache invalidations)."
  value       = aws_cloudfront_distribution.site.id
}

output "bucket_name" {
  description = "S3 bucket holding the site's files."
  value       = aws_s3_bucket.site.id
}

output "certificate_arn" {
  description = "ACM certificate used by CloudFront."
  value       = aws_acm_certificate_validation.site.certificate_arn
}

output "files_uploaded" {
  description = "How many files were uploaded from site_dir."
  value       = length(local.files)
}
