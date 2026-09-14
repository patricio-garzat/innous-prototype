-- fix78: Innous también puede tener un username, para entrar con username
-- O con correo, lo que sea más cómodo — a diferencia de un proveedor
-- (fix75), donde el username REEMPLAZA al correo para el login, aquí es
-- nada más una opción extra: el correo de Innous sigue funcionando igual
-- que siempre.
--
-- La diferencia técnica con fix75: la tabla `suppliers` ya guarda su propio
-- correo en una columna normal, así que resolve_supplier_login_email()
-- podía leerlo directo. Innous no tiene una tabla de "datos de negocio"
-- propia — solo su renglón en `profiles` (rol, nombre, foto) — y el correo
-- real de esa cuenta vive únicamente en auth.users, no en una tabla
-- consultable normalmente. Por eso resolve_innous_login_email() sí necesita
-- juntar profiles con auth.users — sigue siendo seguro exponerla a
-- cualquiera (incluso sin haber iniciado sesión) porque, igual que su
-- contraparte de proveedores, solo regresa un correo (una sola columna) de
-- una sola cuenta, nunca el resto de su información.
--
-- Nota: el username de un proveedor (suppliers.username) y el de un
-- integrante de Innous (profiles.username) viven en índices únicos
-- SEPARADOS — nada impide hoy que alguno de los dos elija el mismo
-- username que ya usa alguien del otro grupo. Con el número de cuentas de
-- Innous que maneja la plataforma (el equipo interno, no hay autoregistro)
-- el riesgo de choque es mínimo; si algún día hiciera falta, se puede
-- unificar en una sola tabla de usernames más adelante.

alter table profiles add column if not exists username text;

create unique index if not exists profiles_username_unique_idx
  on profiles (lower(username))
  where username is not null;

create or replace function resolve_innous_login_email(p_username text)
returns text
language sql
security definer
set search_path = public
stable
as $$
  select u.email
  from profiles p
  join auth.users u on u.id = p.user_id
  where p.role = 'INNOUS' and lower(p.username) = lower(p_username)
  limit 1;
$$;

grant execute on function resolve_innous_login_email(text) to anon, authenticated;
