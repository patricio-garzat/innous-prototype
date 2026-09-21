-- fix116: una sola sesión activa por cuenta — aplica a CLIENT, SUPPLIER e
-- INNOUS por igual, porque el candado vive en `profiles`, que es la tabla
-- compartida por los tres roles.
--
-- Diseño: si alguien ya tiene sesión abierta con una cuenta y otro
-- dispositivo/persona intenta entrar con la misma cuenta, EL INTENTO
-- NUEVO se rechaza (con un mensaje) — la sesión que ya estaba abierta
-- sigue funcionando sin que nadie la interrumpa. Esto es al revés de lo
-- que hacen muchos sistemas de "un solo dispositivo" (que sacan al
-- viejo y dejan entrar al nuevo) — así lo pidió el usuario explícitamente.
--
-- Cómo se decide si una sesión "ya estaba abierta" sigue contando: cada
-- pestaña con sesión activa manda un latido (heartbeat) cada 45s
-- (index.html, startSessionHeartbeat). Si el latido deja de llegar por
-- más de 3 minutos (laptop cerrada, se cerró la pestaña sin dar
-- "Cerrar sesión", crash, etc.), la sesión se considera abandonada y
-- cualquiera puede volver a reclamarla — así nadie queda bloqueado para
-- siempre por un cierre sucio.
--
-- A propósito NO hay un grant de UPDATE directo sobre las columnas nuevas
-- (a diferencia del patrón de username/email/innous_access de fixes
-- anteriores): las tres funciones de abajo son el ÚNICO camino para
-- tocarlas, para que el chequeo de "¿ya hay alguien?" sea atómico del
-- lado del servidor (una fila de Postgres se bloquea sola durante el
-- UPDATE) y nadie pueda simplemente escribir su propio
-- active_session_id sin pasar por ahí.

alter table profiles add column if not exists active_session_id uuid;
alter table profiles add column if not exists session_last_seen_at timestamptz;

-- Intenta tomar la sesión para el usuario autenticado que llama (auth.uid()
-- — nunca un id que mande el cliente, así nadie puede reclamar la sesión
-- de otra cuenta). Solo tiene éxito si no hay nadie activo ahorita, o si
-- la sesión que había ya se puso vieja (más de p_stale_after_seconds sin
-- latido).
create or replace function claim_session(p_session_id uuid, p_stale_after_seconds int default 180)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claimed boolean;
begin
  update profiles
    set active_session_id = p_session_id, session_last_seen_at = now()
    where user_id = auth.uid()
      and (active_session_id is null or session_last_seen_at < now() - (p_stale_after_seconds || ' seconds')::interval)
    returning true into v_claimed;
  return coalesce(v_claimed, false);
end;
$$;
grant execute on function claim_session(uuid, int) to authenticated;

-- Latido: solo "cuenta" si el session_id que manda todavía es el que
-- Postgres tiene como activo — si ya no lo es (alguien más lo reclamó
-- mientras esta pestaña estaba dormida/sin conexión), regresa false y
-- index.html cierra la sesión localmente con un aviso.
create or replace function renew_session_heartbeat(p_session_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean;
begin
  update profiles set session_last_seen_at = now()
    where user_id = auth.uid() and active_session_id = p_session_id
    returning true into v_ok;
  return coalesce(v_ok, false);
end;
$$;
grant execute on function renew_session_heartbeat(uuid) to authenticated;

-- Se llama al cerrar sesión voluntariamente (App.logOut, ANTES de
-- sb.auth.signOut — auth.uid() ya no resolvería después). Solo limpia si
-- el session_id todavía coincide, para no borrarle por accidente la
-- sesión a alguien más que ya haya vuelto a reclamar la cuenta.
create or replace function clear_session(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update profiles set active_session_id = null, session_last_seen_at = null
    where user_id = auth.uid() and active_session_id = p_session_id;
end;
$$;
grant execute on function clear_session(uuid) to authenticated;
