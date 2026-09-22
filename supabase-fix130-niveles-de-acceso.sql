-- fix130: de 2 niveles (admin/viewer) a 4 (owner/admin/editor/viewer).
--
--   owner   — control total, INCLUYE manejar el equipo (crear compañeros,
--             cambiarles el nivel, borrarlos) — EXCLUSIVO del owner, ni
--             siquiera un admin normal puede. Patricio (patricio@innous.com)
--             queda como el primer owner al correr esto; desde la UI puede
--             poner a alguien más como owner también si quiere.
--   admin   — todo lo que un admin ya podía hacer hoy, MENOS manejar el
--             equipo (eso es solo del owner).
--   editor  — "básicamente un empleado": puede recibir RFQs, mandarlos a
--             cotizar (invitar proveedores), y autorizar pedidos. Nada
--             más — no puede editar ni borrar nada, ni la info de nadie.
--   viewer  — igual que hoy, sin cambios: ve todo, no puede tocar nada
--             salvo su propia foto/username/contraseña.
--
-- Mismo diseño en dos capas que fix97 (la UI en index.html oculta/
-- deshabilita lo que no aplica, PERO lo que de verdad importa es esto:
-- que ni con herramientas técnicas se pueda saltar).

------------------------------------------------------------
-- 1) La columna acepta los 4 valores ahora.
------------------------------------------------------------

alter table profiles drop constraint if exists profiles_innous_access_check;
alter table profiles add constraint profiles_innous_access_check
  check (innous_access in ('owner','admin','editor','viewer'));

-- Patricio queda como el primer (y por ahora único) owner. Ajusta el
-- correo aquí si para cuando corras esto ya es otro distinto.
update profiles set innous_access = 'owner'
where role = 'INNOUS' and user_id = (
  select id from auth.users where email in ('patricio@innous.com','patricio@innous.com.mx') limit 1
);

------------------------------------------------------------
-- 2) is_innous_admin() ahora también es cierto para owner (owner incluye
--    todo lo que admin ya podía hacer, más el manejo del equipo) — y la
--    función nueva is_innous_owner(), para lo exclusivo del owner.
------------------------------------------------------------

create or replace function is_innous_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(
    (select innous_access in ('owner','admin') from profiles where user_id = auth.uid() and role = 'INNOUS'),
    false
  );
$$;

create or replace function is_innous_owner()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(
    (select innous_access = 'owner' from profiles where user_id = auth.uid() and role = 'INNOUS'),
    false
  );
$$;
grant execute on function is_innous_owner() to authenticated;

------------------------------------------------------------
-- 3) El candado real de "solo el owner cambia niveles de acceso" — un
--    trigger, no una política RLS, a propósito: así protege la columna
--    innous_access sin importar por dónde se intente escribir (la app de
--    hoy, la consola del navegador, lo que sea) — profiles.innous_access
--    ya tenía un grant de columna abierto a authenticated desde fix99
--    (necesario para que cada quien pueda seguir editando su propio
--    nombre/foto/username en el mismo UPDATE), así que sin esto, un
--    admin normal podría auto-ascenderse a owner llamando la API
--    directo, sin pasar por cambiarTeammateAccess/su candado de UI.
------------------------------------------------------------

create or replace function enforce_innous_access_owner_only()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.innous_access is distinct from OLD.innous_access and not is_innous_owner() then
    raise exception 'Solo el owner de INNOUS puede cambiar el nivel de acceso.';
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_enforce_innous_access_owner_only on profiles;
create trigger trg_enforce_innous_access_owner_only
  before update on profiles
  for each row execute function enforce_innous_access_owner_only();

------------------------------------------------------------
-- 4) Borrar un compañero: exclusivo del owner ahora (antes bastaba con
--    is_innous_admin()). innous_delete_account también se usa para
--    borrar CLIENTES y PROVEEDORES (App.deleteCustomer/deleteSupplier) —
--    esos NO se restringen a owner (el usuario nunca lo pidió), así que
--    la función mira el rol del perfil que se está borrando antes de
--    decidir qué nivel exigir.
------------------------------------------------------------

create or replace function innous_delete_account(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_role user_role;
begin
  select role into v_role from profiles where user_id = p_user_id;
  if v_role = 'INNOUS' then
    if not is_innous_owner() then
      raise exception 'Solo el owner de INNOUS puede eliminar cuentas de compañeros.';
    end if;
  else
    if not is_innous_admin() then
      raise exception 'Not authorized';
    end if;
  end if;
  delete from customers where user_id = p_user_id;
  delete from suppliers where user_id = p_user_id;
  delete from profiles where user_id = p_user_id;
  delete from auth.users where id = p_user_id;
end;
$$;

create or replace function create_innous_teammate_profile(
  p_user_id uuid,
  p_display_name text,
  p_email text,
  p_access text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_innous_owner() then
    raise exception 'Solo el owner de INNOUS puede crear cuentas de compañeros.';
  end if;
  if p_access not in ('owner','admin','editor','viewer') then
    raise exception 'Nivel de acceso inválido.';
  end if;
  insert into profiles (user_id, role, display_name, email, innous_access)
  values (p_user_id, 'INNOUS', p_display_name, p_email, p_access);
end;
$$;

------------------------------------------------------------
-- 5) Las dos acciones que SÍ tiene permitidas un Editor — nunca a través
--    de las tablas directo (esas se quedan bloqueadas para editor/viewer
--    por igual, ver fix97), sino por estas dos funciones SECURITY
--    DEFINER, que son las únicas que un editor puede usar para escribir
--    algo. index.html ya llama a estas dos en vez de los writes directos
--    de antes (ver App.sendRfqToSuppliers/App.authorizeProject).
------------------------------------------------------------

create or replace function innous_send_rfq_to_suppliers(
  p_project_id text,
  p_supplier_ids uuid[],
  p_status text,
  p_target_price_markup_pct numeric default null,
  p_target_price_exchange_rate numeric default null,
  p_target_price_supplier_budget_mxn numeric default null,
  p_items jsonb default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_access text;
begin
  select innous_access into v_access from profiles where user_id = auth.uid() and role = 'INNOUS';
  if v_access is null or v_access not in ('owner','admin','editor') then
    raise exception 'Not authorized';
  end if;

  insert into invited_suppliers (project_id, supplier_id)
  select p_project_id, sid from unnest(p_supplier_ids) as sid;

  insert into supplier_quotes (project_id, supplier_id, status)
  select p_project_id, sid, 'pending' from unnest(p_supplier_ids) as sid;

  update projects set
    status = p_status::rfq_status,
    target_price_markup_pct = coalesce(p_target_price_markup_pct, target_price_markup_pct),
    target_price_exchange_rate = coalesce(p_target_price_exchange_rate, target_price_exchange_rate),
    target_price_supplier_budget_mxn = coalesce(p_target_price_supplier_budget_mxn, target_price_supplier_budget_mxn),
    items = coalesce(p_items, items)
  where id = p_project_id;
end;
$$;
grant execute on function innous_send_rfq_to_suppliers(text, uuid[], text, numeric, numeric, numeric, jsonb) to authenticated;

create or replace function innous_authorize_project(p_project_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_access text;
  v_supplier_id uuid;
  v_project_name text;
begin
  select innous_access into v_access from profiles where user_id = auth.uid() and role = 'INNOUS';
  if v_access is null or v_access not in ('owner','admin','editor') then
    raise exception 'Not authorized';
  end if;

  select selected_supplier_id, project_name into v_supplier_id, v_project_name
  from projects where id = p_project_id;
  if v_supplier_id is null then
    raise exception 'No supplier selected for this project';
  end if;

  update projects set innous_authorized_at = now() where id = p_project_id and innous_authorized_at is null;

  insert into notifications (user_id, title, body, project_id)
  values (
    v_supplier_id,
    'Tu cotización para ' || p_project_id || ' fue seleccionada',
    'INNOUS autorizó el proyecto "' || v_project_name || '" — ya puedes empezar a trabajar en él. Descarga tu Orden de Compra desde el pedido.',
    p_project_id
  );
end;
$$;
grant execute on function innous_authorize_project(text) to authenticated;
