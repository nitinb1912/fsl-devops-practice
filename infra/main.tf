terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.5.0"
}

provider "aws" {
  region = var.region
}

# Generate random suffix to ensure unique bucket names
resource "random_id" "suffix" {
  byte_length = 4
}

# S3 bucket for website files
resource "aws_s3_bucket" "site_bucket" {
  bucket = "${var.bucket_name}-${var.env}-${random_id.suffix.hex}"

  tags = {
    Name        = "${var.bucket_name}-${var.env}"
    Environment = var.env
  }
}

# Enable static website hosting configuration
resource "aws_s3_bucket_website_configuration" "site_config" {
  bucket = aws_s3_bucket.site_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

# Allow public access so CloudFront can read via OAI
resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket                  = aws_s3_bucket.site_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Create a CloudFront Origin Access Identity (OAI)
resource "aws_cloudfront_origin_access_identity" "this" {
  comment = "Allow CloudFront to access S3 bucket securely"
}

# Allow CloudFront OAI to read from S3
resource "aws_s3_bucket_policy" "allow_oai_access" {
  bucket = aws_s3_bucket.site_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontReadAccess",
        Effect    = "Allow",
        Principal = {
          CanonicalUser = aws_cloudfront_origin_access_identity.this.s3_canonical_user_id
        },
        Action    = "s3:GetObject",
        Resource  = "${aws_s3_bucket.site_bucket.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.public_access]
}

# CloudFront distribution for the app
resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  default_root_object = "index.html"

  origin {
    domain_name = aws_s3_bucket.site_bucket.bucket_regional_domain_name
    origin_id   = "s3origin"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.this.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3origin"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

  tags = {
    Environment = var.env
  }
}

# S3 bucket for CloudFront logs
resource "aws_s3_bucket" "logs" {
  bucket = "${var.bucket_name}-logs-${random_id.suffix.hex}"

  tags = {
    Name        = "${var.bucket_name}-logs"
    Environment = var.env
  }
}