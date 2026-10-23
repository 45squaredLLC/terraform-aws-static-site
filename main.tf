# A static website on AWS with no servers: a private S3 bucket behind CloudFront,
# an HTTPS certificate from ACM, and DNS in Route 53. You bring the HTML, CSS and JS.

locals {
  slug      = replace(var.domain, ".", "-")
  zone_name = coalesce(var.zone_name, var.domain)
  hosts     = var.include_www ? [var.domain, "www.${var.domain}"] : [var.domain]
  files     = fileset(var.site_dir, "**")
  has_404   = fileexists("${var.site_dir}/404.html")

  content_types = {
    html        = "text/html; charset=utf-8"
    htm         = "text/html; charset=utf-8"
    css         = "text/css; charset=utf-8"
    js          = "text/javascript; charset=utf-8"
    mjs         = "text/javascript; charset=utf-8"
    map         = "application/json"
    json        = "application/json"
    xml         = "application/xml; charset=utf-8"
    txt         = "text/plain; charset=utf-8"
    csv         = "text/csv; charset=utf-8"
    pdf         = "application/pdf"
    svg         = "image/svg+xml"
    png         = "image/png"
    jpg         = "image/jpeg"
    jpeg        = "image/jpeg"
    gif         = "image/gif"
    webp        = "image/webp"
    avif        = "image/avif"
    ico         = "image/x-icon"
    mp4         = "video/mp4"
    webm        = "video/webm"
    mp3         = "audio/mpeg"
    woff        = "font/woff"
    woff2       = "font/woff2"
    ttf         = "font/ttf"
    otf         = "font/otf"
    wasm        = "application/wasm"
    webmanifest = "application/manifest+json"
  }

  # Pages, and CSS/JS with a plain name like style.css, are re-checked by browsers
  # every 5 minutes, so an edit shows up for returning visitors without a hard
  # refresh. CSS/JS with a content hash in the name (a Vite/React build's
  # index-BxK3d9aQ.js, main.8f3a2b1c.css) never change under that name, so they're
  # cached for a year. Images, fonts and media for 30 days. The edge keeps pages
  # longer only when we clear its cache on every upload.
  page_types        = ["html", "htm", "json", "xml", "txt", "webmanifest", "map"]
  code_types        = ["css", "js", "mjs", "wasm"]
  page_cache        = var.invalidate_on_change ? "public, max-age=300, s-maxage=86400" : "public, max-age=300, s-maxage=300"
  fingerprint_cache = "public, max-age=31536000, immutable"
  media_cache       = "public, max-age=2592000"

  # A name segment of 8+ letters/digits that includes a digit, right before the
  # extension: "-BxK3d9aQ.js", ".8f3a2b1c.css". Plain names ("style.css",
  # "bootstrap.min.js") don't match.
  fingerprinted = {
    for f in local.files : f => can(regex("[.-][A-Za-z0-9_]*[0-9][A-Za-z0-9_]*\\.[a-z0-9]+$", f)) && try(length(regex("[.-]([A-Za-z0-9_]+)\\.[a-z0-9]+$", f)[0]) >= 8, false)
  }

  file_ext = { for f in local.files : f => lower(reverse(split(".", f))[0]) }

  cache_control = {
    for f in local.files : f => (
      contains(local.page_types, local.file_ext[f]) ? local.page_cache :
      contains(local.code_types, local.file_ext[f]) ? (local.fingerprinted[f] ? local.fingerprint_cache : local.page_cache) :
      local.media_cache
    )
  }

  # Changes to a file's bytes or its cache header both clear the CDN cache, so a
  # cache-policy change (e.g. a module upgrade) reaches visitors right away.
  content_hash = sha1(join(",", [for f in local.files : "${f}:${filemd5("${var.site_dir}/${f}")}:${local.cache_control[f]}"]))

  # AWS managed CloudFront cache policy "CachingOptimized".
  cache_optimized = "658327ea-f89d-4fab-a63d-7e88639e58f6"
}

data "aws_route53_zone" "this" {
  name         = local.zone_name
  private_zone = false
}

# --------------------------------------------------------------------------- #
# Bucket: private. Only this CloudFront distribution can read it.
# --------------------------------------------------------------------------- #

resource "aws_s3_bucket" "site" {
  bucket = coalesce(var.bucket_name, "static-site-${local.slug}")
  tags   = var.tags
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "CloudFrontRead"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.site.arn}/*"
      Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.site.arn } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.site]
}

resource "aws_s3_object" "file" {
  for_each = local.files

  bucket        = aws_s3_bucket.site.id
  key           = each.value
  source        = "${var.site_dir}/${each.value}"
  source_hash   = filemd5("${var.site_dir}/${each.value}")
  content_type  = lookup(local.content_types, local.file_ext[each.value], "application/octet-stream")
  cache_control = local.cache_control[each.value]
  tags          = var.tags
}

# --------------------------------------------------------------------------- #
# HTTPS certificate. CloudFront only uses certificates from us-east-1.
# --------------------------------------------------------------------------- #

resource "aws_acm_certificate" "site" {
  provider                  = aws.us_east_1
  domain_name               = var.domain
  subject_alternative_names = var.include_www ? ["www.${var.domain}"] : []
  validation_method         = "DNS"
  tags                      = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  # Keyed by host name, which is known before apply; the record itself is not.
  for_each = toset(local.hosts)

  zone_id = data.aws_route53_zone.this.zone_id
  name    = one([for o in aws_acm_certificate.site.domain_validation_options : o.resource_record_name if o.domain_name == each.key])
  type    = one([for o in aws_acm_certificate.site.domain_validation_options : o.resource_record_type if o.domain_name == each.key])
  records = [one([for o in aws_acm_certificate.site.domain_validation_options : o.resource_record_value if o.domain_name == each.key])]
  ttl     = 300
  # ACM uses the same validation record for every certificate on a name, so an
  # earlier certificate may have created it already. Same value, safe to adopt.
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "site" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.site.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# --------------------------------------------------------------------------- #
# CloudFront
# --------------------------------------------------------------------------- #

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "static-site-${local.slug}"
  description                       = "S3 access for ${var.domain}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "router" {
  name    = "static-site-${local.slug}"
  runtime = "cloudfront-js-2.0"
  comment = "Redirects and clean URLs for ${var.domain}"
  publish = true
  code = templatefile("${path.module}/router.js.tftpl", {
    config = jsonencode({
      domain    = var.domain
      www       = var.include_www
      spa       = var.spa
      redirects = var.redirects
    })
  })
}

resource "aws_cloudfront_response_headers_policy" "site" {
  name = "static-site-${local.slug}"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = false
      override                   = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "SAMEORIGIN"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    dynamic "content_security_policy" {
      for_each = var.content_security_policy == null ? [] : [var.content_security_policy]
      content {
        content_security_policy = content_security_policy.value
        override                = true
      }
    }
  }
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2and3"
  price_class         = var.price_class
  default_root_object = "index.html"
  aliases             = local.hosts
  comment             = "Static site: ${var.domain}"
  tags                = var.tags

  origin {
    origin_id                = "s3"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id           = "s3"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = local.cache_optimized
    response_headers_policy_id = aws_cloudfront_response_headers_policy.site.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.router.arn
    }
  }

  # A private bucket answers 403 for a file that doesn't exist. Show the site's
  # 404.html when it has one, otherwise the home page, with a real 404 status.
  dynamic "custom_error_response" {
    for_each = [403, 404]
    content {
      error_code            = custom_error_response.value
      response_code         = 404
      response_page_path    = local.has_404 ? "/404.html" : "/index.html"
      error_caching_min_ttl = 60
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.site.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# Clear the edge cache after an upload so the new version shows up right away.
resource "terraform_data" "invalidate" {
  count = var.invalidate_on_change ? 1 : 0

  triggers_replace = [local.content_hash, aws_cloudfront_distribution.site.id]

  provisioner "local-exec" {
    command = "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.site.id} --paths '/*' >/dev/null"
  }

  depends_on = [aws_s3_object.file]
}

# --------------------------------------------------------------------------- #
# DNS: point the domain (and www) at CloudFront.
# --------------------------------------------------------------------------- #

resource "aws_route53_record" "site" {
  for_each = var.create_dns_records ? {
    for pair in setproduct(local.hosts, ["A", "AAAA"]) : "${pair[0]} ${pair[1]}" => {
      name = pair[0]
      type = pair[1]
    }
  } : {}

  zone_id         = data.aws_route53_zone.this.zone_id
  name            = each.value.name
  type            = each.value.type
  allow_overwrite = var.replace_existing_records

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}
