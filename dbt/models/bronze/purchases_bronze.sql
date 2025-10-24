-- purchases_bronze: pass-through model from Snowpipe staging table
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
from {{ source('raw', 'raw_purchases_staging') }}
