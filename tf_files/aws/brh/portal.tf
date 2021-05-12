locals {
	# Maps file extensions to mime types
	# Need to add more if needed
  mime_type_mappings = {
    html = "text/html",
    js   = "text/javascript",
    css  = "text/css"
  }
}


data "external" "frontend_build" {
	program = ["bash", "-c", <<EOT
(npm ci && npm run build) >&2 && echo "{\"dest\": \"dist\"}"
EOT
]
	working_dir = var.portal_source_dir
}

data "aws_iam_policy_document" "s3_bucket_policy" {
  statement {
    sid = "1"

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "${aws_s3_bucket.frontend_bucket.arn}/*",
    ]

    principals {
      type = "AWS"

      identifiers = [
        aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn,
      ]
    }
  }
}

resource "aws_s3_bucket" "frontend_bucket" {
	  force_destroy = "true"
    #bucket = "${var.domain_name}-bucket"
    acl    = "private"
    versioning {
        enabled = true
    }
}

resource "aws_s3_bucket_policy" "policy" {
  bucket = "${aws_s3_bucket.frontend_bucket.id}"
  policy = data.aws_iam_policy_document.s3_bucket_policy.json
}


resource "aws_s3_bucket_object" "frontend_object" {
  for_each = fileset("${data.external.frontend_build.working_dir}/build", "*")
	key    = each.value
	source = "${data.external.frontend_build.working_dir}/build/${each.value}"
	bucket = aws_s3_bucket.frontend_bucket.bucket

  etag         = filemd5("${data.external.frontend_build.working_dir}/build/${each.value}")
  content_type = lookup(local.mime_type_mappings, concat(regexall("\\.([^\\.]*)$", each.value), [[""]])[0][0], "application/octet-stream")
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  depends_on = [
    aws_s3_bucket.frontend_bucket
  ]

  origin {
    domain_name = aws_s3_bucket.frontend_bucket.bucket_regional_domain_name
    origin_id   = "s3-cloudfront"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases = [var.domain_name]

  default_cache_behavior {
    allowed_methods = [
      "GET",
      "HEAD",
    ]

    cached_methods = [
      "GET",
      "HEAD",
    ]

    target_origin_id = "s3-cloudfront"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
    acm_certificate_arn      = var.aws_acm_certificate
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1"
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    error_caching_min_ttl = 0
    response_page_path    = "/"
  }

  wait_for_deployment = false
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  #comment = "access-identity-${var.domain_name}.s3.amazonaws.com"
}