# Retail Streaming Medallion Architecture

**Project:** `retail-streaming-medallion`

**Purpose (short):** Simulate continuous retail purchase events, land them to S3 (raw), perform basic cleaning with AWS Glue (bronze), auto-ingest into Snowflake via Snowpipe, then use dbt to create Silver (conformed) and Gold (analytics-ready) layers ready for BI reporting. The repo follows the Medallion architecture: **Raw -> Bronze -> Silver -> Gold**.

---

## File tree (suggested)

```
retail-streaming-medallion/
├── README.md  <-- this document
├── infra/
│   ├── snowflake/
│   │   ├── create_stage_and_pipe.sql
│   │   └── snowpipe_auto_ingest_instructions.md
│   └── aws/
│       ├── glue_job_role_policy.json
│       └── s3_bucket_policy.json
├── src/
│   ├── simulator/
│   │   ├── generate_events.py        # continuous simulation -> upload to S3
│   │   └── requirements.txt
│   ├── glue/
│   │   ├── glue_job_cleaner.py       # AWS Glue PySpark script (bronze)
│   │   └── glue_job_requirements.txt
│   └── snowflake/
│       └── trigger_snowpipe.py       # alternative: call Snowpipe REST API
├── dbt/
│   ├── dbt_project.yml
│   ├── profiles.yml.example
│   └── models/
│       ├── bronze/
│       │   └── purchases_bronze.sql
│       ├── silver/
│       │   └── purchases_silver.sql
│       └── gold/
│           └── purchases_gold.sql
└── docs/
    └── local_dev_instructions.md
```

---

# Architecture Overview (brief)

1. **Simulator**: Python script emits continuous JSON purchase events and uploads them to an S3 `raw/` prefix (date-partitioned files). Files are compact newline-delimited JSON (NDJSON) or small JSON batches.
2. **Raw (S3)**: Raw event files are immutable — appended as objects under `s3://<bucket>/raw/yyyy=YYYY/mm=MM/dd=DD/HH=HH/<uuid>.json`.
3. **Bronze (Glue)**: AWS Glue job reads raw JSON, performs minimal schema enforcement, removes clearly invalid records, writes Parquet to `s3://<bucket>/bronze/...` partitioned by day.
4. **Snowpipe**: Snowpipe configured on Snowflake stage that watches Bronze (or Raw) S3 prefix. When new objects arrive it auto-ingests into a Snowflake **staging table** (external table or staged COPY INTO). We'll show SQL to create a stage and pipe using Snowpipe REST or S3 event notifications.
5. **Silver (dbt)**: dbt models in `silver/` clean & conform (normalize datetimes, user_id resolution, product lookup), written to Snowflake schema `silver`.
6. **Gold (dbt)**: Aggregations and BI-ready tables (daily sales rollups, product/category metrics) in `gold/` schema.

---

# Quick prerequisites

- AWS account with permissions for S3, IAM, Glue, Lambda (if using Lambda for Snowpipe notifications), SNS/SQS.
- Snowflake account with an administrator or appropriate privileges.
- dbt-core and dbt-snowflake installed locally (or use dbt Cloud).
- Python 3.9+ for simulator and optional Snowpipe invoker.

---

# 1) Simulator: `generate_events.py`

Save under `src/simulator/generate_events.py`.

```python
"""Generate streaming retail purchase events and upload to S3 in small NDJSON files."""
import json
import time
import uuid
import random
import argparse
from datetime import datetime, timezone
import boto3

# Basic event schema
PRODUCTS = [
    {"product_id": "P100", "category": "electronics", "price": 199.99},
    {"product_id": "P101", "category": "clothing", "price": 29.99},
    {"product_id": "P102", "category": "home", "price": 49.99},
    {"product_id": "P103", "category": "grocery", "price": 3.49},
]


def random_event():
    p = random.choice(PRODUCTS)
    qty = random.randint(1, 5)
    total = round(p["price"] * qty, 2)
    return {
        "event_id": str(uuid.uuid4()),
        "ts": datetime.now(timezone.utc).isoformat(),
        "store_id": f"S{random.randint(1,10):03}",
        "customer_id": f"C{random.randint(1,5000):06}",
        "product_id": p["product_id"],
        "category": p["category"],
        "price": p["price"],
        "quantity": qty,
        "total_amount": total,
    }


def upload_batch(s3_client, bucket, prefix, batch_events):
    key = f"{prefix}/{datetime.utcnow().strftime('%Y/%m/%d/%H%M%S')}_{uuid.uuid4().hex[:8]}.json"
    body = "\n".join(json.dumps(e) for e in batch_events)
    s3_client.put_object(Bucket=bucket, Key=key, Body=body.encode("utf-8"))
    return key


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bucket", required=True, help="S3 bucket name")
    parser.add_argument("--prefix", default="raw", help="S3 prefix, default 'raw'")
    parser.add_argument("--batch-size", type=int, default=20)
    parser.add_argument("--sleep", type=float, default=2.0, help="seconds between batches")
    args = parser.parse_args()

    s3 = boto3.client("s3")
    print("Starting simulator. Ctrl+C to stop.")
    try:
        while True:
            batch = [random_event() for _ in range(args.batch_size)]
            key = upload_batch(s3, args.bucket, args.prefix, batch)
            print(f"Uploaded {len(batch)} events to s3://{args.bucket}/{key}")
            time.sleep(args.sleep)
    except KeyboardInterrupt:
        print("Simulator stopped.")

if __name__ == '__main__':
    main()
```

**Notes**:
- Use AWS credentials via environment variables or AWS CLI configured profile.
- Run locally or from an EC2 container. Install `boto3`.

Example run:

```bash
python generate_events.py --bucket my-retail-streaming-bucket --prefix raw --batch-size 25 --sleep 1.5
```

---

# 2) AWS Glue job (Bronze): `glue_job_cleaner.py`

Save under `src/glue/glue_job_cleaner.py`.

```python
# Glue PySpark (Glue v3) script - reads NDJSON from raw/, validates basic schema, writes Parquet to bronze/
from awsglue.context import GlueContext
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from awsglue.utils import getResolvedOptions
import sys

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'INPUT_S3', 'OUTPUT_S3'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session

input_s3 = args['INPUT_S3']  # s3://bucket/raw/
output_s3 = args['OUTPUT_S3']  # s3://bucket/bronze/

# Read newline-delimited JSON
df = spark.read.json(input_s3)

# Minimal cleaning: drop rows with null event_id or ts, cast columns
clean = (
    df.filter(F.col('event_id').isNotNull())
      .filter(F.col('ts').isNotNull())
      .withColumn('ts', F.to_timestamp('ts'))
      .withColumn('price', F.col('price').cast('double'))
      .withColumn('quantity', F.col('quantity').cast('int'))
      .withColumn('total_amount', F.col('total_amount').cast('double'))
)

# Add partition columns
clean = clean.withColumn('dt', F.date_format(F.col('ts'), 'yyyy-MM-dd'))

# Write as partitioned Parquet
(clean.write
     .mode('append')
     .partitionBy('dt')
     .parquet(output_s3))

print('Glue job finished')
```

**Glue setup notes**:
- Package dependencies: none special (uses Spark built-ins). If you add third-party libs, bundle as wheel on S3.
- Configure job to run on events (trigger) or schedule. You can run Glue on demand to process recent raw objects.

---

# 3) Snowflake Stage + Snowpipe

There are two common approaches:
- **S3 event notifications -> AWS SQS -> Snowpipe** (recommended for auto-ingest). Snowflake provides an ARN integration and you configure notifications to call Snowpipe.
- **Manual COPY INTO** or scheduled ingestion if auto-ingest isn't desired.

Place SQL in `infra/snowflake/create_stage_and_pipe.sql`:

```sql
-- 1) Create storage integration (run as ACCOUNTADMIN)
CREATE OR REPLACE STORAGE INTEGRATION s3_int_example
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = S3
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = '<AWS_ROLE_ARN_FOR_SNOWFLAKE>'
  STORAGE_ALLOWED_LOCATIONS = ('s3://my-retail-streaming-bucket/bronze/');

-- 2) Create stage
CREATE OR REPLACE STAGE retail_bronze_stage
  URL='s3://my-retail-streaming-bucket/bronze/'
  STORAGE_INTEGRATION = s3_int_example
  FILE_FORMAT = (TYPE = 'PARQUET');

-- 3) Create target table and pipe
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
```

**Notes**:
- Replace `<AWS_ROLE_ARN_FOR_SNOWFLAKE>` with the role Snowflake will assume.
- Configure S3 event notifications to publish to the SNS/SQS topic Snowflake monitors (see Snowflake docs for Auto-Ingest S3 notifications). The `infra/snowflake/snowpipe_auto_ingest_instructions.md` file should contain step-by-step (we include it in `infra/snowflake` folder).

---

# 4) Snowpipe REST (alternative) invoker

If you prefer to programmatically notify Snowpipe, include `src/snowflake/trigger_snowpipe.py`:

```python
"""Trigger Snowpipe REST API to ingest a single file into a pipe."""
import requests
import time
import json
import argparse
from urllib.parse import quote_plus

# You will need Snowflake account info and private key for JWT auth OR use snowflake-connector to call REST.
# Implementing the full JWT signing flow is beyond this example; instead use snowflake-connector or the built-in auto-ingest.
print('Use Snowflake auto-ingest via S3 notifications or follow Snowflake docs for REST API JWT authentication.')
```


---

# 5) dbt project (Silver & Gold)

Place under `/dbt`.

`dbt_project.yml` (minimal):

```yaml
name: retail_streaming
version: '1.0'
config-version: 2
profile: retail_profile
source-paths: ["models"]
model-paths: ["models"]
target-path: "target"
clean-targets: ["target"]

models:
  retail_streaming:
    +materialized: table
    bronze:
      +schema: bronze
    silver:
      +schema: silver
    gold:
      +schema: gold
```

`profiles.yml.example` (copy to `~/.dbt/profiles.yml` and fill):

```yaml
retail_profile:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: <account>
      user: <user>
      password: <password or use keypair auth>
      role: <role>
      database: <database>
      warehouse: <warehouse>
      schema: bronze
      threads: 4
      client_session_keep_alive: False
```

### dbt models

`models/bronze/purchases_bronze.sql`:

```sql
-- simple pass-through view of the raw staging table
select
  event_id,
  ts::timestamp_ntz as ts,
  store_id,
  customer_id,
  product_id,
  category,
  price,
  quantity,
  total_amount,
  dt::date as dt
from {{ source('snowflake_schema','raw_purchases_staging') }}
```

`models/silver/purchases_silver.sql`:

```sql
with base as (
  select * from {{ ref('purchases_bronze') }}
),
normalized as (
  select
    event_id,
    ts,
    store_id,
    customer_id,
    product_id,
    lower(category) as category,
    price,
    quantity,
    total_amount,
    date_trunc('day', ts) as day
  from base
  where event_id is not null and ts is not null
)

select * from normalized
```

`models/gold/purchases_gold.sql`:

```sql
with daily as (
  select
    day,
    category,
    count(*) as transactions,
    sum(total_amount) as revenue,
    sum(quantity) as units_sold
  from {{ ref('purchases_silver') }}
  group by 1,2
)

select * from daily
```

**Notes**: Replace `{{ source('snowflake_schema','raw_purchases_staging') }}` with your `sources.yml` definition (not included here). You may instead directly `ref` the Snowflake table using `dbt` `external` sources.

---

# 6) Running locally (developer flow)

1. Create S3 bucket: `my-retail-streaming-bucket`.
2. Configure IAM role for Snowflake and create a storage integration in Snowflake (see `infra/snowflake/create_stage_and_pipe.sql`).
3. Start simulator to upload to `s3://.../raw/`.
4. Run Glue job (either hand-trigger or on schedule) to read `raw/` and write `bronze/` (Parquet). Alternatively, for faster iteration, you can run the Glue script as a local PySpark job (adjust paths to local).
5. Configure Snowpipe auto-ingest to watch `s3://.../bronze/` and load to `raw_purchases_staging`.
6. Configure dbt profiles and run `dbt run --select bronze+` then `dbt run --select silver+` and `dbt run --select gold+`.

Commands:

```bash
# simulator
python src/simulator/generate_events.py --bucket my-retail-streaming-bucket --prefix raw --batch-size 25 --sleep 1.5

# dbt (from dbt folder)
dbt deps
dbt seed
dbt run --select purchases_bronze
dbt run --select purchases_silver
dbt run --select purchases_gold
```

---

# 7) Security & IAM notes

- Use least-privilege IAM roles for Glue to access S3.
- For Snowflake Auto-Ingest, create an IAM role Snowflake can assume, and limit it to the specific S3 prefix.
- Set S3 bucket policies to allow only necessary principals.

---

# 8) Observability & troubleshooting

- Enable S3 access logs for troubleshooting.
- Glue job logs available in CloudWatch.
- Snowflake `COPY_HISTORY` and `LOAD` views show ingestion errors.
- Use dbt `--debug` to debug connection issues.

---

# 9) Next steps / enhancements

- Implement idempotent ingestion (use event_id as dedupe key in Snowflake using `MERGE`).
- Add CDC or streaming ingestion using Kinesis Data Firehose to S3 or direct Snowflake Kinesis connector.
- Add product dimension tables and enrich with lookups in Silver layer.
- Add automated tests in dbt (schema tests, unique, not_null).

---

# 10) Example configuration snippets & templates

See the `infra/` and `dbt/` folders for starter SQL and IAM JSON templates. Customize for your accounts.

---

If you want, I can now:
- Generate the full repo files (simulator script, Glue script, Snowflake SQL, dbt models) in a GitHub-ready format and zip them for download; or
- Provide CloudFormation/Terraform for creating S3, IAM, Glue and Snowflake resources; or
- Add dbt tests, sources.yml, and documented SQL docs for each model.

Tell me which next step you want and I'll produce the files accordingly.

