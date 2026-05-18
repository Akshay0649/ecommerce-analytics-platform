# Dashboard cookbook

Once `make up && make seed && make dbt-build` succeeds, point Metabase
(http://localhost:3000) at the warehouse:

- Host: `postgres`
- Port: `5432`
- Database: `analytics`
- User: `bi_reader` / Password: `bi_reader` (read-only on marts)

Below are the canonical questions each mart answers.

## Executive (Finance)

Source: `mart_finance.fct_revenue_daily`

```sql
-- Last 90 days revenue with 7-day moving average
select
    order_date,
    sum(gross_revenue) as revenue,
    avg(sum(gross_revenue)) over (order by order_date rows 6 preceding) as ma7
from mart_finance.fct_revenue_daily
where order_date >= current_date - 90
group by 1
order by 1;
```

## Margin by category

Source: `mart_finance.fct_margin_by_category`

```sql
select parent_category_name,
       sum(revenue) as revenue,
       sum(margin)  as margin,
       round(sum(margin)/nullif(sum(revenue),0), 4) as margin_pct
from mart_finance.fct_margin_by_category
where order_date >= current_date - 30
group by 1
order by margin desc;
```

## Cohort retention heatmap

Source: `mart_marketing.fct_customer_cohorts`

Pivot in Metabase: rows = `cohort_month`, columns = `months_since_first_order`,
value = `active_customers`.

## RFM segments

Source: `mart_marketing.dim_customers_rfm`

```sql
select rfm_segment, count(*) as customers,
       round(avg(monetary)::numeric, 2) as avg_ltv
from mart_marketing.dim_customers_rfm
group by 1
order by avg_ltv desc;
```

## Funnel waterfall

Source: `mart_marketing.fct_funnel_daily`

Aggregate over the last 30 days, render as a funnel chart on
`sessions → product_views → add_to_carts → checkouts → purchases`.

## Channel attribution

Source: `mart_marketing.fct_channel_attribution`

```sql
select utm_source,
       sum(orders_count) as orders,
       sum(attributed_revenue) as revenue,
       round(sum(attributed_margin)/nullif(sum(attributed_revenue),0), 4) as margin_pct
from mart_marketing.fct_channel_attribution
where order_date >= current_date - 30
group by 1
order by revenue desc;
```
