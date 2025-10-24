# Terraform to provision AWS components for Retail Streaming

This Terraform creates:
- S3 bucket for raw/bronze data
- IAM role for Snowflake (Snowflake must be able to assume this role) with restricted S3 permissions
- Glue job resource (script expected at s3://<bucket>/glue/scripts/glue_job_cleaner.py)
- SNS topic and SQS queue for S3 notifications (Snowpipe auto-ingest)

Usage:

1. Update `variables.tf` or pass vars via CLI to set a unique S3 bucket name and Snowflake AWS principal.
2. `terraform init`
3. `terraform apply`

After apply:
- Upload `src/glue/glue_job_cleaner.py` to `s3://<bucket>/glue/scripts/` so Glue job can access it.
- Configure Snowflake storage integration using the role ARN output by Terraform.
- Configure Snowflake to use SQS (or SNS) for auto-ingest notifications per Snowflake docs.
