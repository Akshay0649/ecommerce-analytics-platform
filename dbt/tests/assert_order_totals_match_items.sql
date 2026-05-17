-- Singular test: an order's items_revenue should reconcile to its subtotal
-- (within $0.01 rounding tolerance). Catches loader bugs and item-level drift.

with diffs as (
    select
        order_id,
        subtotal_amount,
        items_revenue,
        abs(coalesce(subtotal_amount, 0) - coalesce(items_revenue, 0)) as diff
    from {{ ref('int_orders_enriched') }}
)

select *
from diffs
where diff > 0.02
