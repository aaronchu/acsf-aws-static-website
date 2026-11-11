# `acsf-aws-static-website` Terraform Module

## Purpose

Establish a static website hosted on AWS at minimal cost and complexity.

## Inputs

| Variable | Type | Example | Description |
| - | - | - | - |
| `bucket_name` | `string` | `my-website-bucket` | (required) The name of the S3 bucket to create. |
| `primary_fqdn` | `string` | `mydomainname.com` | (required) The primary FQDN for the website. |
| `alternative_fqdn` | `string` | `www.mydomainname.com` | The alternative FQDN for the website (needs to be in the same zone as the primary FQDN). Default value is empty. |
| `dns_zone_name` | `string` | `mydomainname.com` |(required) The name of the DNS zone to create. |
| `redirect_alternative_fqdn` | `bool` | `true` | 301-redirect `alternative_fqdn` to `primary_fqdn` (keeping path and query string) instead of serving the site on both. Default `false`. |
| `not_found_page_path` | `string` | `/404.html` | Page to serve, with status 404, for missing objects. Default empty, which serves S3's 403 error. |
| `browser_cache_control` | `string` | `public, max-age=3600` | `Cache-Control` header for objects that don't set their own. Default empty, which sends none. |

## Behavior

Responses are compressed (gzip and Brotli) and cached at the edge with the AWS-managed `CachingOptimized` policy.

## Usage

Using the module:

```
module "static_website" {
  source           = "git::https://github.com/aaronchu/acsf-aws-static-website.git"
  primary_fqdn     = "mydomainname.com"
  alternative_fqdn = "www.mydomainname.com"
  dns_zone_name    = "mydomainname.com"
  bucket_name      = "mydomainname-static-website"

  providers = {
    aws = aws.use1 # required for everything to work (set this provider up in us-east-1)
  }

  depends_on = [module.zones] # optional, if you set up your zones elsewhere
}
```

To create a provider in `us-east-1`:

```
provider "aws" {
  alias               = "use1"
  region              = "us-east-1"
  allowed_account_ids = ["YOUR_ACCOUNT_ID"]
  assume_role {
    role_arn     = "arn:aws:iam::YOUR_ACCOUNT_ID:role/YOUR_TERRAFORM_ROLE"
    session_name = "Terraform"
    duration     = "1h"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.7 |
| aws | ~> 5.0 |

## Providers

`aws` (see requirements)

## Notes

1. Intended for hobbyist use only.
2. Built with `terraform` version `1.5.x` and intent to move to [`opentofu`](https://opentofu.org/) eventually.
