data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "website_bucket" {
  bucket = var.bucket_name # Replace with your unique bucket name
}

resource "aws_s3_bucket" "logs_bucket" {
  bucket = "${var.bucket_name}-logs" # Replace with your unique bucket name
}

resource "aws_s3_bucket_acl" "logs_bucket" {
  bucket = aws_s3_bucket.logs_bucket.bucket

  acl    = "private"
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
  name         = var.dns_zone_name
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
    domain_name = aws_s3_bucket.website_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
    origin_id   = "S3-${aws_s3_bucket.website_bucket.bucket}"
  }

  aliases = var.alternative_fqdn != "" ? [var.primary_fqdn, var.alternative_fqdn] : [var.primary_fqdn]

  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.website_bucket.bucket}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
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
    acm_certificate_arn            = aws_acm_certificate_validation.website_cert_validation.certificate_arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2021"
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
  count = var.alternative_fqdn != "" ? 1 : 0

  alias {
    name                   = aws_cloudfront_distribution.website_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.website_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}
