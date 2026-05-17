-- Per session, downstream funnel stages cannot exceed upstream ones.
-- e.g. a session that purchased must also have reached checkout.

select session_id
from {{ ref('int_session_funnel') }}
where (reached_purchase    and not reached_checkout)
   or (reached_checkout    and not reached_add_to_cart)
   or (reached_add_to_cart and not reached_product_view)
