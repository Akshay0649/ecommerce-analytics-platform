{# RFM segmentation. Quintile scoring across Recency, Frequency, Monetary.
   Score 555 = best, 111 = worst. as_of_date is configurable via dbt vars. #}

{%- set as_of = var('as_of_date') -%}

with base as (
    select
        c.customer_id,
        c.email,
        c.cohort_month,
        c.acquisition_channel,
        coalesce(c.lifetime_orders, 0)                              as frequency,
        coalesce(c.lifetime_revenue, 0)                             as monetary,
        c.last_order_ts,
        case when c.last_order_ts is not null
             then date('{{ as_of }}') - c.last_order_ts::date
        end                                                         as recency_days
    from {{ ref('dim_customers') }} c
    where c.lifetime_orders > 0
),

scored as (
    select
        *,
        ntile(5) over (order by recency_days asc)                   as r_score,  -- lower days = better
        ntile(5) over (order by frequency desc)                     as f_score,
        ntile(5) over (order by monetary desc)                      as m_score
    from base
)

select
    customer_id,
    email,
    cohort_month,
    acquisition_channel,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    (r_score * 100 + f_score * 10 + m_score)                       as rfm_score,
    case
        when r_score >= 4 and f_score >= 4 and m_score >= 4 then 'Champions'
        when r_score >= 4 and f_score >= 3                  then 'Loyal'
        when r_score >= 4                                   then 'Recent'
        when r_score <= 2 and f_score >= 3                  then 'At Risk'
        when r_score <= 2 and m_score >= 4                  then 'Cannot Lose Them'
        when r_score <= 2                                   then 'Hibernating'
        else 'Needs Attention'
    end                                                            as rfm_segment
from scored
