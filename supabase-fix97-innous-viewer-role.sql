-- fix97: cuentas de INNOUS con dos niveles de acceso — 'admin' (como hoy,
-- ve y hace todo) y 'viewer' (ve absolutamente todo lo mismo, pero no
-- puede crear/editar/borrar/mandar nada — "que no me le muevan a nada").
--
-- Diseño en dos capas, a propósito:
--  1) UI (index.html) — oculta/deshabilita botones de escritura para
--     viewer. Cómodo, pero alguien con conocimientos técnicos podría
--     saltárselo llamando a la API de Supabase directo.
--  2) Esta migración (la que de verdad importa) — bloquea la escritura a
--     nivel de base de datos con Row Level Security, exactamente con el
--     mismo rigor que ya separa cliente/proveedor/INNOUS entre sí. Ni con
--     herramientas técnicas se puede saltar esto.
--
-- Estrategia para no arriesgar nada que ya funciona: NO se toca ninguna
-- política existente. Se agregan políticas "RESTRICTIVE" nuevas — a
-- diferencia de las políticas normales (PERMISSIVE, que se combinan con
-- OR), una RESTRICTIVE se combina con AND: además de cumplir alguna
-- política permisiva de las que ya existen, TAMBIÉN hay que cumplir esta.
-- Cada una está escrita como "no eres INNOUS (no te afecta) O eres admin"
-- — así un CLIENT/SUPPLIER jamás se ve afectado, solo INNOUS, y de esos
-- solo el que no sea admin.

------------------------------------------------------------
-- 1) La columna y la función que dicen quién es admin
------------------------------------------------------------

alter table profiles add column if not exists innous_access text
  check (innous_access in ('admin','viewer'));
-- Todas las cuentas de INNOUS que ya existen hoy quedan como 'admin' —
-- nadie pierde acceso a nada que ya tenía por correr esta migración.
update profiles set innous_access = 'admin' where role = 'INNOUS' and innous_access is null;

-- Aprovechado también para mostrar el correo de cada compañero de INNOUS
-- en la pantalla de "Equipo" (profiles no tenía columna de correo — a
-- diferencia de customers/suppliers, que sí — porque nunca hizo falta
-- hasta ahora). Se rellena una sola vez para las cuentas que ya existen;
-- las nuevas la reciben directo en create_innous_teammate_profile más abajo.
alter table profiles add column if not exists email text;
update profiles p set email = u.email
  from auth.users u
  where u.id = p.user_id and p.email is null;

create or replace function is_innous_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(
    (select innous_access = 'admin' from profiles where user_id = auth.uid() and role = 'INNOUS'),
    false
  );
$$;
grant execute on function is_innous_admin() to authenticated;

------------------------------------------------------------
-- 2) Bloquear escritura para viewer en las tablas que hoy tienen una
--    política "ALL" para INNOUS (ve Y edita con la misma condición) —
--    hay que dejar el SELECT tal cual (viewer sigue viendo todo) y solo
--    restringir INSERT/UPDATE/DELETE.
------------------------------------------------------------

do $$
declare
  t text;
  tables text[] := array[
    'activity_log', 'customers', 'invited_suppliers', 'messages_general',
    'messages_project_client', 'messages_project_supplier',
    'order_milestones', 'order_ratings', 'orders', 'projects',
    'shortlist', 'supplier_quotes', 'suppliers'
  ];
begin
  foreach t in array tables loop
    execute format('drop policy if exists %I on %I', 'fix97 viewer no inserta', t);
    execute format(
      'create policy %I on %I as restrictive for insert with check (my_role() <> ''INNOUS''::user_role or is_innous_admin())',
      'fix97 viewer no inserta', t);

    execute format('drop policy if exists %I on %I', 'fix97 viewer no actualiza', t);
    execute format(
      'create policy %I on %I as restrictive for update using (my_role() <> ''INNOUS''::user_role or is_innous_admin()) with check (my_role() <> ''INNOUS''::user_role or is_innous_admin())',
      'fix97 viewer no actualiza', t);

    execute format('drop policy if exists %I on %I', 'fix97 viewer no borra', t);
    execute format(
      'create policy %I on %I as restrictive for delete using (my_role() <> ''INNOUS''::user_role or is_innous_admin())',
      'fix97 viewer no borra', t);
  end loop;
end $$;

------------------------------------------------------------
-- 3) profiles — casos especiales: un viewer SÍ puede seguir editando su
--    PROPIO perfil (nombre/foto/username — su cuenta personal, no es
--    "mover" nada del negocio), pero no el de alguien más; y no puede
--    borrar ningún perfil (ni el suyo, por este mismo camino).
------------------------------------------------------------

drop policy if exists "fix97 viewer solo edita su propio perfil" on profiles;
create policy "fix97 viewer solo edita su propio perfil" on profiles as restrictive for update
  using (my_role() <> 'INNOUS'::user_role or is_innous_admin() or user_id = auth.uid())
  with check (my_role() <> 'INNOUS'::user_role or is_innous_admin() or user_id = auth.uid());

drop policy if exists "fix97 viewer no borra perfiles" on profiles;
create policy "fix97 viewer no borra perfiles" on profiles as restrictive for delete
  using (my_role() <> 'INNOUS'::user_role or is_innous_admin());

------------------------------------------------------------
-- 4) settings — el único caso fuera del patrón "ALL" que faltaba.
------------------------------------------------------------

drop policy if exists "fix97 viewer no edita settings" on settings;
create policy "fix97 viewer no edita settings" on settings as restrictive for update
  using (my_role() <> 'INNOUS'::user_role or is_innous_admin());

------------------------------------------------------------
-- 5) Storage: el bucket account-docs (Constancias fiscales de proveedor,
--    fix46) — viewer sigue viendo los documentos, no puede subir/borrar.
--    Acotado explícitamente a este bucket para no tocar ningún otro
--    (project-files, chat-files, etc. no son exclusivos de INNOUS).
------------------------------------------------------------

drop policy if exists "fix97 viewer no sube a account-docs" on storage.objects;
create policy "fix97 viewer no sube a account-docs" on storage.objects as restrictive for insert
  with check (bucket_id <> 'account-docs' or is_innous_admin());

drop policy if exists "fix97 viewer no borra de account-docs" on storage.objects;
create policy "fix97 viewer no borra de account-docs" on storage.objects as restrictive for delete
  using (bucket_id <> 'account-docs' or is_innous_admin());

------------------------------------------------------------
-- 6) Las dos funciones SECURITY DEFINER que ya existían y solo pedían
--    "seas INNOUS" (no distinguían admin/viewer) para hacer algo — se
--    endurecen a "seas admin de INNOUS". Mismo cuerpo de siempre, solo
--    cambia la condición de autorización.
------------------------------------------------------------

-- fix14/fix51 — borra una cuenta completa (perfil + credencial real).
create or replace function innous_delete_account(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not is_innous_admin() then
    raise exception 'Not authorized';
  end if;
  delete from customers where user_id = p_user_id;
  delete from suppliers where user_id = p_user_id;
  delete from profiles where user_id = p_user_id;
  delete from auth.users where id = p_user_id;
end;
$$;

-- fix19/fix33 — le manda una notificación a alguien.
create or replace function innous_send_notification(p_user_ids uuid[], p_title text, p_body text, p_project_id text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_innous_admin() then
    raise exception 'Not authorized';
  end if;
  insert into notifications (user_id, title, body, project_id)
  select uid, p_title, p_body, p_project_id from unnest(p_user_ids) as uid;
end;
$$;

------------------------------------------------------------
-- 7) Nueva: crear la cuenta de un compañero de INNOUS.
--
-- Por qué es una función y no un insert normal desde la app (a diferencia
-- de App.createSupplierAccount, que sí inserta directo): ese flujo de
-- proveedor funciona porque CUALQUIERA puede auto-registrarse como
-- SUPPLIER/CLIENT (es una política a propósito abierta, ver "usuario crea
-- su propio perfil" — Innous solo lo hace en su nombre). Nadie debe poder
-- auto-registrarse como INNOUS — esa política de auto-registro de hecho
-- EXCLUYE 'INNOUS' explícitamente (solo permite role IN ('CLIENT',
-- 'SUPPLIER')). La única puerta para crear una cuenta de INNOUS es esta
-- función: corre bajo la sesión de quien la llama (el admin que ya tiene
-- sesión iniciada), así que sí puede verificar "¿el que está llamando esto
-- es admin?" con is_innous_admin() — algo que un insert directo bajo la
-- sesión del usuario NUEVO (que todavía no tiene perfil) no podría hacer.
--
-- App.createInnousTeammate() en index.html hace el auth.signUp() del
-- nuevo usuario con un cliente de Supabase aislado (mismo patrón que
-- App.createSupplierAccount) y luego llama a ESTA función con la sesión
-- normal del admin para crear su fila de profiles.
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
  if not is_innous_admin() then
    raise exception 'Solo un administrador de INNOUS puede crear cuentas de compañeros.';
  end if;
  if p_access not in ('admin','viewer') then
    raise exception 'Nivel de acceso inválido.';
  end if;
  insert into profiles (user_id, role, display_name, email, innous_access)
  values (p_user_id, 'INNOUS', p_display_name, p_email, p_access);
end;
$$;
grant execute on function create_innous_teammate_profile(uuid, text, text, text) to authenticated;
