-- Create storage integration, stage and pipe for Snowpipe auto-ingest.
-- Replace placeholders with your account-specific values.
CREATE OR REPLACE STORAGE INTEGRATION s3_int_example
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = S3
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = '<AWS_ROLE_ARN_FOR_SNOWFLAKE>'
  STORAGE_ALLOWED_LOCATIONS = ('s3://my-retail-streaming-bucket/bronze/');

CREATE OR REPLACE STAGE retail_bronze_stage
  URL='s3://my-retail-streaming-bucket/bronze/'
  STORAGE_INTEGRATION = s3_int_example
  FILE_FORMAT = (TYPE = 'PARQUET');

CREATE OR REPLACE TABLE raw_purchases_staging (
  event_id STRING,
  ts TIMESTAMP_TZ,
  store_id STRING,
  customer_id STRING,
  product_id STRING,
  category STRING,
  price FLOAT,
  quantity INT,
  total_amount FLOAT,
  dt DATE
);

CREATE OR REPLACE PIPE retail_bronze_pipe
  AUTO_INGEST = TRUE
  AS
  COPY INTO raw_purchases_staging
  FROM @retail_bronze_stage
  FILE_FORMAT = (TYPE = 'PARQUET')
  ON_ERROR = 'CONTINUE';
