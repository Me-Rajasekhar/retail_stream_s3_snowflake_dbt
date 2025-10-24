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
