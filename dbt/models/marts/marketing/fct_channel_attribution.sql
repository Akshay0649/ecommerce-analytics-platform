{# Last-touch attribution by utm_source. For each completed order linked via a
   web_events.purchase row, attribute revenue to the session's utm_source.
   Orders with no matching session bucket as 'unattributed'. #}

with purchase_events as (
    select distinct on (e.order_id)
        e.order_id,
        s.utm_source,
        s.utm_medium,
        s.utm_campaign,
        s.device
    from {{ ref('stg_web_events') }} e
    join {{ ref('stg_web_sessions') }} s on e.session_id = s.session_id
    where e.event_name = 'purchase' and e.order_id is not null
    order by e.order_id, e.event_ts
),

orders as (
    select * from {{ ref('fct_orders') }} where is_completed
)

select
    o.order_date,
    coalesce(pe.utm_source, 'unattributed')                       as utm_source,
    coalesce(pe.utm_medium, 'unattributed')                       as utm_medium,
    coalesce(pe.utm_campaign, 'unattributed')                     as utm_campaign,
    count(*)                                                      as orders_count,
    count(distinct o.customer_id)                                 as unique_customers,
    sum(o.gross_revenue)::numeric(14,2)                           as attributed_revenue,
    sum(o.gross_margin)::numeric(14,2)                            as attributed_margin
from orders o
left join purchase_events pe on o.order_id = pe.order_id
group by 1, 2, 3, 4
