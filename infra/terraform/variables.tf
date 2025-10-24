variable "aws_region" {
  description = "AWS region to deploy resources in"
  type = string
  default = "us-east-1"
}

variable "s3_bucket_name" {
  description = "Name for the S3 bucket (must be globally unique)"
  type = string
  default = "my-retail-streaming-bucket-123456"
}

variable "snowflake_aws_principal" {
  description = "AWS principal (ARN) for Snowflake to assume this role. Replace with Snowflake-provided ARN or account root." 
  type = string
  default = "arn:aws:iam::123456789012:root"
}
