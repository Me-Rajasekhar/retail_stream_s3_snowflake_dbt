# Snowpipe Auto-Ingest Instructions (high level)
1. Create an IAM role in AWS and allow Snowflake account to assume the role (see Snowflake docs).
2. Fill STORAGE_AWS_ROLE_ARN in `create_stage_and_pipe.sql` and run as ACCOUNTADMIN in Snowflake.
3. Configure S3 Event Notification to the SNS topic or SQS queue that Snowflake supports for auto-ingest.
4. Grant required S3 permissions on the Bronze prefix only.
5. Test by dropping a Parquet file into the bronze prefix and checking the Snowflake pipe COPY_HISTORY.
