-- Hasta ahora, client_select_quote le inventaba un transportista y un
-- número de rastreo AL AZAR desde el momento en que se creaba el pedido
-- (mucho antes de que existiera un envío real) — por eso el cliente podía
-- ver datos de "rastreo" que ni siquiera correspondían a nada real.
--
-- Ahora esos dos campos quedan vacíos al crear el pedido, y Innous los
-- captura a mano — con los datos reales de la guía — justo en el momento
-- en que marca el pedido como "Shipped" (ver App.openShipOrderModal /
-- App.confirmShipOrder en la app). Todo lo demás de la función queda igual.
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
          null, null,
          v_delivery_date - interval '14 days', v_delivery_date, v_quote_number)
  on conflict (project_id) do nothing;
end;
$$;
grant execute on function client_select_quote(text, uuid) to authenticated;
