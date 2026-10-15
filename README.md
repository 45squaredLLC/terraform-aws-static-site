# terraform-aws-static-site

Put a static website on AWS with one `terraform apply`. You bring the HTML, CSS and JavaScript; the module sets up everything else:

- a **private S3 bucket** for the files (nobody can reach it except CloudFront)
- **CloudFront** in front of it: HTTPS, HTTP/2 and HTTP/3, gzip/brotli, IPv6, edge caching
- a free **HTTPS certificate** from ACM, validated through DNS automatically
- **Route 53** records pointing your domain (and `www`) at the site
- **clean URLs** (`/about/` serves `about/index.html`), a `www` to bare-domain redirect, and your own redirects
- **single-page app mode** for React, Vue and Svelte routers
- security headers (HSTS, nosniff, frame and referrer policy), with an optional Content-Security-Policy
- a cache clear after every upload, so changes show up right away

There is no server to patch, nothing to restart, and for a small site the bill is usually under a dollar or two a month (see [Cost](#cost)).

It works with anything that ends up as files in a folder: hand-written HTML, a site generated with ChatGPT, or the build output of an app made in Lovable, Bolt, v0, Vite, Astro or a static Next.js export.

## Quick start

You need an AWS account, [Terraform](https://developer.hashicorp.com/terraform/install) 1.5 or newer, the [AWS CLI](https://aws.amazon.com/cli/) signed in (`aws configure`), and your domain's DNS in a Route 53 hosted zone.

```hcl
provider "aws" {
  region = "us-east-1"
}

# CloudFront only accepts certificates from us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "site" {
  source = "github.com/45squaredLLC/terraform-aws-static-site"

  domain   = "example.com"
  site_dir = "${path.module}/site" # the folder with your index.html

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

output "url" {
  value = module.site.url
}
```

```bash
terraform init
terraform apply
```

The first apply takes 5 to 15 minutes, mostly CloudFront spreading to its edge locations. After that, edit your files and run `terraform apply` again: only changed files are uploaded, and the cache is cleared.

### Apps built with Lovable, Bolt, v0 or Vite

These are single-page apps. Build them first, point `site_dir` at the build output, and turn on `spa`:

```bash
npm install
npm run build        # writes dist/ (Vite, Lovable, Bolt) or build/ (Create React App)
```

```hcl
module "site" {
  source = "github.com/45squaredLLC/terraform-aws-static-site"

  domain   = "example.com"
  site_dir = "${path.module}/../my-app/dist"
  spa      = true

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}
```

With `spa = true`, a path without a file extension (`/dashboard/settings`) is answered with `index.html` so the app's router takes over, and refreshing a deep link no longer shows an error.

### A subdomain

```hcl
  domain      = "app.example.com"
  zone_name   = "example.com"   # the hosted zone the record goes in
  include_www = false
```

### Replacing a site that is already live

Nothing live changes by accident. If your domain already points somewhere else, the first apply stops with an error about the existing record instead of taking it over. To switch safely:

1. Apply with `create_dns_records = false`. Everything is built, and the site answers at the `cloudfront_url` output.
2. Check the site there.
3. Apply with `create_dns_records = true` and `replace_existing_records = true`. The domain now points at CloudFront.

Use `redirects` to keep old links working:

```hcl
  redirects = {
    "/about-us.html" = "/about/"
    "/old-blog"      = "https://blog.example.com/"
  }
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `domain` | The site's domain, e.g. `example.com` or `app.example.com`. | required |
| `site_dir` | Folder holding the finished site. Must contain `index.html`. | required |
| `zone_name` | Route 53 hosted zone, when it differs from `domain`. | `domain` |
| `include_www` | Also serve `www.<domain>`, redirecting to the bare domain. | `true` |
| `spa` | Single-page app mode: extensionless paths get `/index.html`. | `false` |
| `redirects` | Map of old path to new path or URL (301). | `{}` |
| `content_security_policy` | Content-Security-Policy header value. | `null` (off) |
| `bucket_name` | S3 bucket name. | `static-site-<domain>` |
| `price_class` | CloudFront price class. | `PriceClass_100` |
| `create_dns_records` | Point the domain at CloudFront. | `true` |
| `replace_existing_records` | Allow overwriting existing A/AAAA records. | `false` |
| `invalidate_on_change` | Clear the CloudFront cache after an upload (runs the AWS CLI). | `true` |
| `tags` | Tags for every resource that takes them. | `{}` |

## Outputs

| Name | Description |
|---|---|
| `url` | `https://<domain>` |
| `cloudfront_url` | Test address that works before DNS points at the site |
| `distribution_id` | CloudFront distribution ID |
| `bucket_name` | S3 bucket holding the files |
| `certificate_arn` | ACM certificate ARN |
| `files_uploaded` | Number of files uploaded from `site_dir` |

## Things that don't come along

A static host serves files. Anything a builder platform did on its own servers needs a home of its own:

- **Contact forms.** A form that posted to the builder's backend will stop working. Use a form service, or a small API (API Gateway and Lambda) that you point the form at.
- **Secret keys in the front end.** Anything in your JavaScript can be read by every visitor. API keys for paid services (OpenAI, Stripe secret keys, database admin keys) must live in a backend, never in the site files.
- **Environment variables.** Vite and similar tools bake `VITE_*` values into the build. Set them before `npm run build`, not in AWS.
- **Server-rendered pages.** Next.js server components, API routes and middleware need a server. Use `output: "export"` for a static Next.js build, or host it elsewhere.

## Caching

| Files | Browser | CloudFront |
|---|---|---|
| HTML, JSON, XML, TXT | 5 minutes | 1 day, cleared on every apply |
| CSS, JS, WASM | 1 day | 1 day |
| Images, fonts, media | 30 days | 30 days |

With `invalidate_on_change = false` the edge keeps pages for 5 minutes too, so changes still show up without a cache clear. The invalidation runs `aws cloudfront create-invalidation` on the machine running Terraform with the same credentials, so the AWS CLI must be installed there. The first 1,000 invalidation paths each month are free, and each apply uses one (`/*`).

## Cost

For a typical small business site, close to nothing:

- **Route 53**: $0.50 a month for the hosted zone. Queries for alias records pointing at CloudFront are free.
- **CloudFront**: the always-free tier covers 1 TB of data transfer and 10 million requests a month, plus 2 million CloudFront Function runs.
- **S3**: a few cents a month for a site of a few hundred megabytes.
- **ACM certificate**: free.

Check the [CloudFront](https://aws.amazon.com/cloudfront/pricing/) and [Route 53](https://aws.amazon.com/route53/pricing/) pricing pages for current numbers; your domain registration is separate.

## Tests

```bash
terraform init -backend=false
terraform test                       # plans every scenario against a mocked AWS provider
node --test tests/router.test.mjs    # the CloudFront Function: redirects, clean URLs, SPA mode
```

## Don't want to run it yourself?

[45Squared](https://45squared.com) builds, hosts and looks after websites for small businesses. If you made a site with an AI builder and want it online, fast and maintained without touching Terraform, [get in touch](https://45squared.com/contact/).

## License

MIT
