provider "aws" {
  region = var.aws_region
}

# S3 bucket for raw and bronze data
resource "aws_s3_bucket" "retail_bucket" {
  bucket = var.s3_bucket_name

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Name = "retail-streaming-bucket"
  }
}

# IAM role for Snowflake to assume (Snowflake will need the role ARN)
data "aws_iam_policy_document" "snowflake_trust" {
  statement {
    sid = "AllowSnowflakeAssumeRole"
    effect = "Allow"
    principals {
      type = "AWS"
      identifiers = [var.snowflake_aws_principal] # e.g., arn:aws:iam::123456789012:root or specific Snowflake principal
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "snowflake_integration_role" {
  name = "snowflake_integration_role"
  assume_role_policy = data.aws_iam_policy_document.snowflake_trust.json
  tags = { Name = "snowflake-integration-role" }
}

# IAM policy for the role (restrict to the bronze prefix)
data "aws_iam_policy_document" "snowflake_policy" {
  statement {
    sid = "AllowS3AccessToBronze"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:GetObjectVersion",
      "s3:PutObjectAcl"
    ]
    resources = [
      "${aws_s3_bucket.retail_bucket.arn}",
      "${aws_s3_bucket.retail_bucket.arn}/*"
    ]
    condition {
      test = "StringLike"
      variable = "s3:prefix"
      values = ["bronze/*", "raw/*"]
    }
  }
}

resource "aws_iam_policy" "snowflake_policy_attach" {
  name   = "snowflake-access-policy"
  policy = data.aws_iam_policy_document.snowflake_policy.json
}

resource "aws_iam_role_policy_attachment" "attach_snowflake_policy" {
  role       = aws_iam_role.snowflake_integration_role.name
  policy_arn = aws_iam_policy.snowflake_policy_attach.arn
}

# SNS topic and SQS queue for S3 notifications
resource "aws_sns_topic" "s3_notifications" {
  name = "retail-s3-notifications"
}

resource "aws_sqs_queue" "snowpipe_queue" {
  name = "retail-snowpipe-queue"
}

# Allow SNS to send messages to SQS
resource "aws_sns_topic_subscription" "sns_to_sqs" {
  topic_arn = aws_sns_topic.s3_notifications.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.snowpipe_queue.arn
}

# Allow SNS to publish to SQS (policy)
resource "aws_sqs_queue_policy" "allow_sns" {
  queue_url = aws_sqs_queue.snowpipe_queue.id
  policy    = data.aws_iam_policy_document.sqs_policy.json
}

data "aws_iam_policy_document" "sqs_policy" {
  statement {
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    effect = "Allow"
    actions = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.snowpipe_queue.arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.s3_notifications.arn]
    }
  }
}

# S3 bucket notification to SNS for new objects (bronze prefix)
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.retail_bucket.id

  topic {
    topic_arn = aws_sns_topic.s3_notifications.arn
    events    = ["s3:ObjectCreated:*"]
    filter_prefix = "bronze/"
  }
}

# Glue IAM role
data "aws_iam_policy_document" "glue_assume" {
  statement {
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "glue_role" {
  name = "retail_glue_job_role"
  assume_role_policy = data.aws_iam_policy_document.glue_assume.json
}

resource "aws_iam_role_policy_attachment" "glue_s3_policy" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# Glue job (script needs to be uploaded to S3 manually or via additional resource)
resource "aws_glue_job" "glue_cleaner" {
  name     = "retail_glue_cleaner"
  role_arn = aws_iam_role.glue_role.arn

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.retail_bucket.bucket}/glue/scripts/glue_job_cleaner.py"
  }

  max_capacity = 2
  tags = { Name = "retail-glue-cleaner" }
}
