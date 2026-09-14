-- fix67: estado del mensaje (enviado / entregado / visto) en Mensajes.
--
-- Se agregan dos columnas nuevas a messages_general para poder marcar
-- cuándo un mensaje llegó al aparato de la otra persona (delivered_at) y
-- cuándo esa persona realmente abrió esa conversación y lo vio en pantalla
-- (read_at). Ninguna de las dos se llena sola: el propio portal las va
-- actualizando (ver App.markDelivered / App.markThreadRead en index.html)
-- según la persona dueña de esta conversación (RLS ya lo permite — las
-- políticas de messages_general ya son "for all", así que también cubren
-- este UPDATE, sin necesidad de una política nueva).
--
-- fix67 también empieza a escuchar actualizaciones (UPDATE) de esta tabla
-- por Realtime, además de inserciones — mismo mecanismo que fix66 ya usaba
-- para que los mensajes nuevos aparecieran al instante, ahora extendido
-- para que la palomita de "visto" también le llegue a quien envió el
-- mensaje sin tener que esperar el refresco de cada 12 segundos.

alter table messages_general add column if not exists delivered_at timestamptz;
alter table messages_general add column if not exists read_at timestamptz;
