-- tests/test_total_amount_consistency.sql
select *
from {{ ref('purchases_silver') }}
where abs(total_amount - (price * quantity)) > 0.01
