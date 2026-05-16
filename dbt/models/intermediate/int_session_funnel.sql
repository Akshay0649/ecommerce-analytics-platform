{# Per-session funnel flags: which stages did each session reach? #}

with sessions as (
    select * from {{ ref('stg_web_sessions') }}
),

events as (
    select * from {{ ref('stg_web_events') }}
),

per_session as (
    select
        session_id,
        bool_or(event_name = 'page_view')        as reached_page_view,
        bool_or(event_name = 'view_product')     as reached_product_view,
        bool_or(event_name = 'add_to_cart')      as reached_add_to_cart,
        bool_or(event_name = 'checkout_start')   as reached_checkout,
        bool_or(event_name = 'purchase')         as reached_purchase,
        count(*)                                 as event_count,
        max(case when event_name = 'purchase' then order_id end) as purchase_order_id
    from events
    group by 1
)

select
    s.session_id,
    s.customer_id,
    s.started_at,
    s.session_date,
    s.device,
    s.utm_source,
    s.utm_medium,
    s.utm_campaign,
    s.is_anonymous,
    s.session_minutes,
    coalesce(p.reached_page_view, false)        as reached_page_view,
    coalesce(p.reached_product_view, false)     as reached_product_view,
    coalesce(p.reached_add_to_cart, false)      as reached_add_to_cart,
    coalesce(p.reached_checkout, false)         as reached_checkout,
    coalesce(p.reached_purchase, false)         as reached_purchase,
    coalesce(p.event_count, 0)                  as event_count,
    p.purchase_order_id
from sessions s
left join per_session p on s.session_id = p.session_id
