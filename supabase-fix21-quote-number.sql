-- La cotización formal en PDF (ver fix20) usaba el mismo folio del RFQ
-- (p.ej. "IN-2026-00458") como número de cotización. El cliente pidió que
-- en vez de eso, el folio que aparece en el PDF sea un número de cotización
-- formal, corto y consecutivo, con el formato "IN-0000" (igual que tu
-- plantilla real). Este número se asigna UNA sola vez, en el momento
-- exacto en que el cliente elige la cotización de un proveedor (adentro de
-- client_select_quote), y ya nunca cambia — es el folio oficial de esa
-- cotización/pedido.

-- 1) Columna nueva en orders + la secuencia que reparte los folios.
alter table orders add column if not exists quote_number text;
create sequence if not exists quote_number_seq start with 0 minvalue 0;

-- 2) Folios para pedidos que ya existían antes de este cambio, en el orden
--    en que se creó su RFQ (para que el más viejo tenga el número más bajo).
with numbered as (
  select o.project_id, row_number() over (order by p.created_at) - 1 as n
  from orders o
  join projects p on p.id = o.project_id
  where o.quote_number is null
)
update orders set quote_number = 'IN-'||lpad(numbered.n::text, 4, '0')
from numbered where orders.project_id = numbered.project_id;

-- Deja la secuencia por delante del folio más alto ya repartido, para que
-- el siguiente pedido nuevo no choque con uno de los recién asignados arriba.
do $$
declare v_max int;
begin
  select max(substring(quote_number from 4)::int) into v_max from orders where quote_number is not null;
  if v_max is not null then perform setval('quote_number_seq', v_max, true); end if;
end $$;

-- 3) client_select_quote ahora también asigna el folio al crear el pedido.
create or replace function client_select_quote(p_project_id text, p_supplier_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_id uuid;
  v_row shortlist%rowtype;
  v_delivery_location text;
  v_delivery_date date;
  v_supplier_city text;
  v_quote_number text;
begin
  select customer_id, delivery_location, delivery_date into v_customer_id, v_delivery_location, v_delivery_date
    from projects where id = p_project_id;
  if v_customer_id is null or v_customer_id <> auth.uid() then
    raise exception 'Not authorized';
  end if;

  select * into v_row from shortlist where project_id = p_project_id and supplier_id = p_supplier_id;
  if not found then
    raise exception 'Quote not found in shortlist';
  end if;

  select city into v_supplier_city from suppliers where user_id = p_supplier_id;

  update projects set status = 'awarded', selected_supplier_id = p_supplier_id where id = p_project_id;

  v_quote_number := 'IN-'||lpad(nextval('quote_number_seq')::text, 4, '0');

  insert into orders (project_id, supplier_id, status, supplier_cost, customer_price, markup_pct, payment_status, quality_status,
                       logistics_origin, logistics_destination, carrier, tracking, pickup_date, estimated_delivery, quote_number)
  values (p_project_id, p_supplier_id, 'order_confirmed', v_row.supplier_cost, v_row.customer_price, v_row.markup_pct,
          'Awaiting Deposit', 'pending',
          coalesce(v_supplier_city,'Mexico')||', Mexico', v_delivery_location,
          (array['Estafeta Freight','FedEx Freight','Daxxo Logistics','R+L Carriers'])[floor(random()*4+1)::int],
          'TRK-'||floor(random()*900000+100000)::text,
          v_delivery_date - interval '14 days', v_delivery_date, v_quote_number)
  on conflict (project_id) do nothing;
end;
$$;
grant execute on function client_select_quote(text, uuid) to authenticated;

-- 4) El cliente necesita poder leer su propio folio (orders_client_view es
--    la única vista de "orders" que el cliente puede leer).
create or replace view orders_client_view with (security_invoker = true) as
  select project_id, status, customer_price, payment_status, quality_status,
         logistics_destination, estimated_delivery, logistics_documents, quote_number
  from orders;
