# Local Development Instructions (quick)

1. Create an S3 bucket (e.g., my-retail-streaming-bucket).
2. Configure AWS credentials locally (AWS CLI or env vars).
3. Create Snowflake storage integration and pipe (see infra/snowflake/create_stage_and_pipe.sql).
4. Install simulator requirements:
   ```bash
   python -m venv .venv
   source .venv/bin/activate
   pip install -r src/simulator/requirements.txt
   ```
5. Run simulator:
   ```bash
   python src/simulator/generate_events.py --bucket my-retail-streaming-bucket --prefix raw --batch-size 20 --sleep 2
   ```
6. Configure and run Glue job to read `s3://my-retail-streaming-bucket/raw/*` and write Parquet to `s3://my-retail-streaming-bucket/bronze/`.
7. Verify Snowpipe loads Parquet files into Snowflake staging table `raw_purchases_staging`.
8. Configure dbt `profiles.yml` (see dbt/profiles.yml.example) and run dbt:
   ```bash
   cd dbt
   pip install dbt-core dbt-snowflake
   dbt run
   dbt test
   ```
