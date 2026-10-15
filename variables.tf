variable "domain" {
  description = "The site's domain, e.g. example.com or app.example.com."
  type        = string
}

variable "site_dir" {
  description = "Folder holding the finished site (index.html, CSS, JS, images). For a React/Vite app this is the build output, usually dist/ or build/. Every file in it is uploaded."
  type        = string

  validation {
    condition     = fileexists("${var.site_dir}/index.html")
    error_message = "site_dir must contain an index.html. For a React/Vite/Next app, run the build first and point site_dir at its output folder."
  }
}

variable "zone_name" {
  description = "Route 53 hosted zone to put the records in. Defaults to the domain itself; set it when the site is on a subdomain (domain = app.example.com, zone_name = example.com)."
  type        = string
  default     = null
}

variable "include_www" {
  description = "Also serve www.<domain>, redirecting it to the bare domain. Usually wanted for an apex domain, not for a subdomain."
  type        = bool
  default     = true
}

variable "spa" {
  description = "Single-page app mode (React, Vue, Svelte routers): any path without a file extension is answered with /index.html so the app's router handles it."
  type        = bool
  default     = false
}

variable "redirects" {
  description = "Permanent (301) redirects, old path => new path or full URL. Handy when replacing an old site: { \"/about-us.html\" = \"/about/\" }."
  type        = map(string)
  default     = {}
}

variable "content_security_policy" {
  description = "Content-Security-Policy header value. Off by default: vibe-coded sites often pull fonts, scripts and images from other sites, and a strict policy silently breaks them. Set it once you know what the site loads."
  type        = string
  default     = null
}

variable "bucket_name" {
  description = "S3 bucket name. Defaults to static-site-<domain with dots as dashes>. Bucket names are global, so set this if the default is taken."
  type        = string
  default     = null
}

variable "price_class" {
  description = "CloudFront price class. PriceClass_100 (North America and Europe edges) is the cheapest; PriceClass_All adds every edge location."
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200 or PriceClass_All."
  }
}

variable "create_dns_records" {
  description = "Point the domain at CloudFront. Set false to test on the CloudFront URL first (output cloudfront_url), then flip it to true to go live."
  type        = bool
  default     = true
}

variable "replace_existing_records" {
  description = "Let Terraform overwrite A/AAAA records that already exist for the domain (your old site). Leave false on the first run so nothing live changes by accident; set true when you are ready to switch over."
  type        = bool
  default     = false
}

variable "invalidate_on_change" {
  description = "Clear the CloudFront cache after an upload so changes show up right away. Runs the AWS CLI (aws cloudfront create-invalidation) on the machine running Terraform, with the same credentials."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags for every resource that takes them."
  type        = map(string)
  default     = {}
}
