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
