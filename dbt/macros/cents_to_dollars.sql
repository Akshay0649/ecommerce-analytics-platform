{# Reusable: convert integer cents to dollar numeric. #}
{% macro cents_to_dollars(column_name, scale=2) -%}
    round(({{ column_name }} / 100.0)::numeric, {{ scale }})
{%- endmacro %}
