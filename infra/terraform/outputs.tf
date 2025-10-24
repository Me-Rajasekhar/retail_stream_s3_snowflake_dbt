output "s3_bucket" {
  value = aws_s3_bucket.retail_bucket.bucket
}

output "snowflake_role_arn" {
  value = aws_iam_role.snowflake_integration_role.arn
}

output "glue_role_arn" {
  value = aws_iam_role.glue_role.arn
}

output "sns_topic_arn" {
  value = aws_sns_topic.s3_notifications.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.snowpipe_queue.id
}
