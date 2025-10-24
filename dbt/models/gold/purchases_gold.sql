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
