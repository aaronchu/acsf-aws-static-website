data "aws_caller_identity" "current" {}

locals {
  redirect_alternative = var.redirect_alternative_fqdn && var.alternative_fqdn != ""
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# Sends browsers a Cache-Control header for objects that don't set their own.
resource "aws_cloudfront_response_headers_policy" "website" {
  count = var.browser_cache_control != "" ? 1 : 0
  name  = "website-${replace(var.bucket_name, ".", "-")}"

  custom_headers_config {
    items {
      header   = "Cache-Control"
      value    = var.browser_cache_control
      override = false
    }
  }
}

# 301-redirects the alternative FQDN (e.g. www) to the primary FQDN, keeping
# the path and query string, so search engines see one site.
resource "aws_cloudfront_function" "redirect_alternative" {
  count   = local.redirect_alternative ? 1 : 0
  name    = "redirect-${replace(var.primary_fqdn, ".", "-")}"
  runtime = "cloudfront-js-2.0"
  comment = "Redirect ${var.alternative_fqdn} to ${var.primary_fqdn}"
  publish = true
  code    = <<-EOT
    function handler(event) {
      var request = event.request;
      var host = request.headers.host ? request.headers.host.value : "";
      if (host.toLowerCase() !== "${var.alternative_fqdn}") return request;
      var qs = Object.keys(request.querystring)
        .map(function (k) {
          var v = request.querystring[k];
          var values = v.multiValue ? v.multiValue : [v];
          return values
            .map(function (m) {
              return m.value === "" ? k : k + "=" + m.value;
            })
            .join("&");
        })
        .join("&");
      return {
        statusCode: 301,
        statusDescription: "Moved Permanently",
        headers: {
          location: {
            value: "https://${var.primary_fqdn}" + request.uri + (qs ? "?" + qs : ""),
          },
        },
      };
    }
  EOT
}

resource "aws_s3_bucket" "website_bucket" {
  bucket = var.bucket_name # Replace with your unique bucket name
}

resource "aws_s3_bucket" "logs_bucket" {
  bucket = "${var.bucket_name}-logs" # Replace with your unique bucket name
}

resource "aws_s3_bucket_acl" "logs_bucket" {
  bucket = aws_s3_bucket.logs_bucket.bucket

  acl = "private"
}

data "aws_iam_policy_document" "website_bucket_policy" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.website_bucket.arn}/*"]

    condition {
      variable = "AWS:SourceArn"
      test     = "StringEquals"
      values   = [aws_cloudfront_distribution.website_distribution.arn]
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "website_bucket" {
  bucket = aws_s3_bucket.website_bucket.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_policy" "website_bucket" {
  bucket = aws_s3_bucket.website_bucket.bucket
  policy = data.aws_iam_policy_document.website_bucket_policy.json
}

resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "website-oac-${aws_s3_bucket.website_bucket.bucket}"
  description                       = "OAC for ${aws_s3_bucket.website_bucket.bucket}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for ${aws_s3_bucket.website_bucket.bucket}"
}

# ACM Certificate
resource "aws_acm_certificate" "website_cert" {
  domain_name               = var.primary_fqdn # Replace with your domain
  validation_method         = "DNS"
  subject_alternative_names = var.alternative_fqdn != "" ? [var.alternative_fqdn] : null # Secondary domain

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_route53_zone" "website_zone" {
  name = var.dns_zone_name
}

# DNS Record for ACM Validation
resource "aws_route53_record" "website_cert_validation" {

  for_each = {
    for dvo in aws_acm_certificate.website_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.website_zone.zone_id # Replace with your Route53 Hosted Zone ID
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

# ACM Certificate Validation
resource "aws_acm_certificate_validation" "website_cert_validation" {
  certificate_arn         = aws_acm_certificate.website_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.website_cert_validation : record.fqdn]
}

resource "aws_cloudfront_distribution" "website_distribution" {
  origin {
    domain_name              = aws_s3_bucket.website_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
    origin_id                = "S3-${aws_s3_bucket.website_bucket.bucket}"
  }

  aliases = var.alternative_fqdn != "" ? [var.primary_fqdn, var.alternative_fqdn] : [var.primary_fqdn]

  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.website_bucket.bucket}"

    # AWS-managed CachingOptimized: no query strings or cookies in the cache
    # key (as before), and gzip/Brotli enabled so `compress` can use both.
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress                   = true
    response_headers_policy_id = var.browser_cache_control != "" ? aws_cloudfront_response_headers_policy.website[0].id : null

    dynamic "function_association" {
      for_each = local.redirect_alternative ? [1] : []
      content {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.redirect_alternative[0].arn
      }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  # The bucket is private and CloudFront may only GetObject, so S3 answers a
  # missing key with 403. Serve the site's own error page with a real 404.
  dynamic "custom_error_response" {
    for_each = var.not_found_page_path != "" ? [403, 404] : []
    content {
      error_code            = custom_error_response.value
      response_code         = 404
      response_page_path    = var.not_found_page_path
      error_caching_min_ttl = 60
    }
  }

  price_class = "PriceClass_100"

  logging_config {
    bucket          = aws_s3_bucket.logs_bucket.bucket_domain_name
    include_cookies = true
    prefix          = "logs/cloudfront"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.website_cert_validation.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

resource "aws_route53_record" "website_primary_dns_record" {
  zone_id = data.aws_route53_zone.website_zone.zone_id
  name    = var.primary_fqdn # Replace with your domain name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.website_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "website_alternative_dns_record" {
  zone_id = data.aws_route53_zone.website_zone.zone_id
  name    = var.alternative_fqdn # Replace with your domain name
  type    = "A"
  count   = var.alternative_fqdn != "" ? 1 : 0

  alias {
    name                   = aws_cloudfront_distribution.website_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.website_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}
