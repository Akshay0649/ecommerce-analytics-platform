-- No order should be dated in the future. Catches clock-skew / timezone bugs.

select order_id, order_ts
from {{ ref('fct_orders') }}
where order_ts > current_timestamp + interval '1 day'
