-- Los proveedores (mexicanos) cotizan en pesos (MXN). El cliente (en
-- EE.UU.) siempre debe ver dólares (USD). Antes de este cambio, el número
-- que el proveedor tecleaba se usaba tal cual como si ya fuera USD.
--
-- Ahora Innous, al comparar cotizaciones, define un tipo de cambio
-- (con un valor por default en Settings, pero siempre editable ahí mismo
-- porque el tipo de cambio real cambia todos los días) y ese es el único
-- momento en que se hace la conversión: de ahí en adelante (shortlist,
-- pedido, margen, cotización formal en PDF) todo vive en USD. El monto
-- original en MXN y el tipo de cambio usado se guardan aparte, solo como
-- referencia de Innous (y del proveedor, para su propio pedido) de cuánto
-- se le debe pagar en su moneda real.

alter table settings add column if not exists default_exchange_rate numeric not null default 17.5;

alter table shortlist add column if not exists supplier_cost_mxn numeric;
alter table shortlist add column if not exists exchange_rate numeric;

alter table orders add column if not exists supplier_cost_mxn numeric;
alter table orders add column if not exists exchange_rate numeric;

-- client_select_quote (fix9) ahora también copia el monto en MXN y el tipo
-- de cambio de la cotización elegida hacia el pedido — todo lo demás queda
-- exactamente igual.
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

  insert into orders (project_id, supplier_id, status, supplier_cost, supplier_cost_mxn, exchange_rate, customer_price, markup_pct, payment_status, quality_status,
                       logistics_origin, logistics_destination, carrier, tracking, pickup_date, estimated_delivery, quote_number)
  values (p_project_id, p_supplier_id, 'order_confirmed', v_row.supplier_cost, v_row.supplier_cost_mxn, v_row.exchange_rate, v_row.customer_price, v_row.markup_pct,
          'Awaiting Deposit', 'pending',
          coalesce(v_supplier_city,'Mexico')||', Mexico', v_delivery_location,
          (array['Estafeta Freight','FedEx Freight','Daxxo Logistics','R+L Carriers'])[floor(random()*4+1)::int],
          'TRK-'||floor(random()*900000+100000)::text,
          v_delivery_date - interval '14 days', v_delivery_date, v_quote_number)
  on conflict (project_id) do nothing;
end;
$$;
grant execute on function client_select_quote(text, uuid) to authenticated;

-- El proveedor puede ver su propio monto en MXN y el tipo de cambio usado
-- (es su propia cotización, no hay nada que esconderle) — sigue sin ver
-- nada del precio final al cliente ni el margen.
-- IMPORTANT: new columns must be appended at the END of the select list —
-- Postgres's CREATE OR REPLACE VIEW refuses to change the name/position of
-- an existing output column (that needs ALTER VIEW ... RENAME COLUMN
-- instead), so supplier_cost_mxn/exchange_rate go last here, not inserted
-- after supplier_cost.
create or replace view orders_supplier_view with (security_invoker = true) as
  select project_id, supplier_id, status, supplier_cost, quality_status,
         quality_documents, quality_certificates, estimated_delivery, supplier_cost_mxn, exchange_rate
  from orders;

-- shortlist_client_view y orders_client_view no se tocan — ya listan sus
-- columnas de forma explícita (nunca "select *"), así que las columnas
-- nuevas de arriba no se filtran hacia el cliente automáticamente.
