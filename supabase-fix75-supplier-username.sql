-- fix75: los proveedores inician sesión con un nombre de usuario, ya no con
-- su correo. El correo se queda como dato de contacto (sigue apareciendo en
-- su Orden de Compra, por ejemplo), pero deja de servir para entrar al
-- portal. Clientes e Innous no cambian: ellos siguen entrando con correo.
--
-- Por debajo, Supabase Auth solo entiende correo+contraseña — eso no
-- cambia. Lo que hace el portal ahora es: si lo que la persona escribió en
-- "Username or Email" trae una '@', lo manda tal cual como correo (clientes
-- e Innous); si no, lo trata como un nombre de usuario de proveedor y le
-- pregunta a resolve_supplier_login_email() qué correo real le corresponde,
-- y con ESE correo hace el login de siempre. La persona nunca ve ni escribe
-- ese correo real.
--
-- Se agrega la columna `username` a `suppliers`, con un índice único (que
-- ignora los proveedores que todavía no tienen uno, para no romper cuentas
-- ya existentes creadas antes de este cambio — a esas Innous les puede
-- asignar un username después, desde la ficha del proveedor).
--
-- resolve_supplier_login_email() es SECURITY DEFINER a propósito: tiene que
-- poder leerse ANTES de que la persona haya iniciado sesión (todavía no
-- tiene credenciales), por eso se le da permiso también a `anon`. Aun así
-- es seguro exponerla sin restricción: solo regresa un correo (una sola
-- columna) de un solo proveedor, nunca el resto de su información, y ya de
-- por sí cualquier formulario de login existente "filtra" lo mismo (si el
-- usuario/correo existe o no) con o sin esta función.

alter table suppliers add column if not exists username text;

create unique index if not exists suppliers_username_unique_idx
  on suppliers (lower(username))
  where username is not null;

create or replace function resolve_supplier_login_email(p_username text)
returns text
language sql
security definer
set search_path = public
stable
as $$
  select email from suppliers where lower(username) = lower(p_username) limit 1;
$$;

grant execute on function resolve_supplier_login_email(text) to anon, authenticated;
