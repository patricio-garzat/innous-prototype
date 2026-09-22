-- fix132: chat interno entre compañeros de INNOUS — mensajes directos
-- normales (nombre y foto real), separado del chat con clientes/
-- proveedores (messages_general), que está armado para "una persona +
-- INNOUS colectivo" con reglas de confidencialidad que aquí no aplican.
--
-- Con TODO lo que ya tiene el chat de clientes/proveedores — fotos,
-- archivos adjuntos, y compartir tarjetas de RFQ/Cotización/Orden de
-- Compra — index.html reutiliza las MISMAS funciones (chatMessagesHtml,
-- chatComposeRowHtml, chatCardHtml, sendChatMessage, sendChatCard, etc.)
-- con key='team:<idDelOtro>' en vez de armar algo aparte, así que esta
-- tabla necesita las mismas columnas que messages_general.
--
-- Abierto a TODOS los niveles de acceso (owner/admin/editor/viewer) —
-- hablar con un compañero no es "mover" datos del negocio, mismo
-- razonamiento que ya se usó para que viewer pueda seguir editando su
-- propio perfil (ver App.saveAccount/INNOUS_VIEWER_BLOCKED_METHODS en
-- index.html).
--
-- Seguro de volver a correr completo (create table if not exists / add
-- column if not exists / create or replace / drop policy if exists).

create table if not exists innous_team_messages (
  id           uuid primary key default gen_random_uuid(),
  sender_id    uuid not null references profiles(user_id) on delete cascade,
  recipient_id uuid not null references profiles(user_id) on delete cascade,
  text         text not null,
  ts           timestamptz not null default now(),
  delivered_at timestamptz,
  read_at      timestamptz,
  check (sender_id <> recipient_id)
);

alter table innous_team_messages add column if not exists attachment_path text;
alter table innous_team_messages add column if not exists attachment_name text;
alter table innous_team_messages add column if not exists card_type text;
alter table innous_team_messages add column if not exists card_project_id text references projects(id);
alter table innous_team_messages drop constraint if exists innous_team_messages_card_type_check;
alter table innous_team_messages add constraint innous_team_messages_card_type_check
  check (card_type is null or card_type in ('rfq','quote','po'));

alter table innous_team_messages enable row level security;

-- Cada quien ve únicamente los mensajes donde participa (los mandó o los
-- recibió) — nunca los de otros dos compañeros entre sí.
drop policy if exists "compañero ve sus propios chats de equipo" on innous_team_messages;
create policy "compañero ve sus propios chats de equipo" on innous_team_messages for select using (
  my_role() = 'INNOUS' and (sender_id = auth.uid() or recipient_id = auth.uid())
);

-- Solo puede mandar como sí mismo, y solo a otra cuenta que también sea
-- de INNOUS (no tendría sentido mandarle un "mensaje de equipo" a un
-- cliente o proveedor por este camino).
drop policy if exists "compañero manda mensajes de equipo" on innous_team_messages;
create policy "compañero manda mensajes de equipo" on innous_team_messages for insert with check (
  my_role() = 'INNOUS' and sender_id = auth.uid()
  and exists (select 1 from profiles p where p.user_id = recipient_id and p.role = 'INNOUS')
);

-- Solo para marcar delivered_at/read_at (App.markTeamChatThreadRead) —
-- cualquiera de los dos participantes puede actualizar esas dos columnas
-- en un mensaje suyo; no hay edición del texto por este camino.
drop policy if exists "compañero marca como visto" on innous_team_messages;
create policy "compañero marca como visto" on innous_team_messages for update using (
  my_role() = 'INNOUS' and (sender_id = auth.uid() or recipient_id = auth.uid())
) with check (
  my_role() = 'INNOUS' and (sender_id = auth.uid() or recipient_id = auth.uid())
);

-- No hay política de DELETE a propósito — nadie borra mensajes de este
-- chat, ni siquiera el owner (si algún día se quiere, se agrega aparte).

-- Adjuntar fotos/archivos reutiliza el bucket 'chat-files' que ya existe
-- (fix34) — sus políticas ya dejan pasar a CUALQUIER cuenta de INNOUS sin
-- importar la ruta ("my_role() = 'INNOUS' OR ..."), así que no hace
-- falta ninguna política de storage nueva aquí.

-- Mensajes al instante (mismo mecanismo que fix66 ya usa para
-- messages_general) — sin este paso, el chat sigue funcionando normal,
-- solo que con el refresco de cada ~12s en vez de al instante.
-- Envuelto en un chequeo (a diferencia de fix66) porque "alter
-- publication ... add table" SÍ truena si ya estaba agregada, y este
-- archivo está pensado para poder correrse otra vez sin problema.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'innous_team_messages'
  ) then
    alter publication supabase_realtime add table innous_team_messages;
  end if;
end $$;
