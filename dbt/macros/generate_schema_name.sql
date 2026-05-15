{#
  Override default schema generation so that mart sub-folders land in their
  configured schemas (mart_core, mart_finance, mart_marketing) rather than
  prefixed with the target's default schema.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set default_schema = target.schema -%}
    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
