{# Daily funnel conversion. Grain: 1 row per (date, utm_source, device). #}

select
    session_date,
    utm_source,
    device,
    count(*)                                                       as sessions,
    sum(case when reached_product_view  then 1 else 0 end)         as product_views,
    sum(case when reached_add_to_cart   then 1 else 0 end)         as add_to_carts,
    sum(case when reached_checkout     then 1 else 0 end)          as checkouts,
    sum(case when reached_purchase     then 1 else 0 end)          as purchases,

    case when count(*) > 0
         then round(sum(case when reached_product_view then 1 else 0 end)::numeric
                    / count(*), 4) end                             as pdp_rate,
    case when sum(case when reached_product_view then 1 else 0 end) > 0
         then round(sum(case when reached_add_to_cart then 1 else 0 end)::numeric
                    / sum(case when reached_product_view then 1 else 0 end), 4)
    end                                                            as atc_rate,
    case when sum(case when reached_add_to_cart then 1 else 0 end) > 0
         then round(sum(case when reached_checkout then 1 else 0 end)::numeric
                    / sum(case when reached_add_to_cart then 1 else 0 end), 4)
    end                                                            as checkout_rate,
    case when sum(case when reached_checkout then 1 else 0 end) > 0
         then round(sum(case when reached_purchase then 1 else 0 end)::numeric
                    / sum(case when reached_checkout then 1 else 0 end), 4)
    end                                                            as purchase_rate,
    case when count(*) > 0
         then round(sum(case when reached_purchase then 1 else 0 end)::numeric
                    / count(*), 4) end                             as session_to_purchase_rate
from {{ ref('int_session_funnel') }}
group by 1, 2, 3
