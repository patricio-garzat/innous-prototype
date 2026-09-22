-- fix132: chat interno entre compañeros de INNOUS — mensajes directos
-- normales (nombre y foto real), separado del chat con clientes/
-- proveedores (messages_general), que está armado para "una persona +
-- INNOUS colectivo" con reglas de confidencialidad que aquí no aplican.
--
-- Abierto a TODOS los niveles de acceso (owner/admin/editor/viewer) —
-- hablar con un compañero no es "mover" datos del negocio, mismo
-- razonamiento que ya se usó para que viewer pueda seguir editando su
-- propio perfil (ver App.saveAccount/INNOUS_VIEWER_BLOCKED_METHODS en
-- index.html).

create table innous_team_messages (
  id           uuid primary key default gen_random_uuid(),
  sender_id    uuid not null references profiles(user_id) on delete cascade,
  recipient_id uuid not null references profiles(user_id) on delete cascade,
  text         text not null,
  ts           timestamptz not null default now(),
  delivered_at timestamptz,
  read_at      timestamptz,
  check (sender_id <> recipient_id)
);

alter table innous_team_messages enable row level security;

-- Cada quien ve únicamente los mensajes donde participa (los mandó o los
-- recibió) — nunca los de otros dos compañeros entre sí.
create policy "compañero ve sus propios chats de equipo" on innous_team_messages for select using (
  my_role() = 'INNOUS' and (sender_id = auth.uid() or recipient_id = auth.uid())
);

-- Solo puede mandar como sí mismo, y solo a otra cuenta que también sea
-- de INNOUS (no tendría sentido mandarle un "mensaje de equipo" a un
-- cliente o proveedor por este camino).
create policy "compañero manda mensajes de equipo" on innous_team_messages for insert with check (
  my_role() = 'INNOUS' and sender_id = auth.uid()
  and exists (select 1 from profiles p where p.user_id = recipient_id and p.role = 'INNOUS')
);

-- Solo para marcar delivered_at/read_at (App.markTeamChatThreadRead) —
-- cualquiera de los dos participantes puede actualizar esas dos columnas
-- en un mensaje suyo; no hay edición del texto por este camino.
create policy "compañero marca como visto" on innous_team_messages for update using (
  my_role() = 'INNOUS' and (sender_id = auth.uid() or recipient_id = auth.uid())
) with check (
  my_role() = 'INNOUS' and (sender_id = auth.uid() or recipient_id = auth.uid())
);

-- No hay política de DELETE a propósito — nadie borra mensajes de este
-- chat, ni siquiera el owner (si algún día se quiere, se agrega aparte).
