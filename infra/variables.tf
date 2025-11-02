variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "S3 bucket name"
  type        = string
  default     = "fsl-devops-demo-site"
}

variable "env" {
  description = "Environment name (e.g., devel or stage)"
  default     = "devel"
}