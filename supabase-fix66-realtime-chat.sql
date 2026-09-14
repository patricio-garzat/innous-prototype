-- fix66: mensajes instantáneos (en vivo) en Mensajes.
--
-- Antes, un mensaje nuevo solo aparecía del otro lado hasta el siguiente
-- "poll" cada 12 segundos (y se saltaba ese ciclo si la persona estaba
-- escribiendo). Ahora el portal se suscribe directo a los mensajes nuevos
-- vía Supabase Realtime (WebSockets) — aparecen al instante, como en
-- WhatsApp — pero SOLO para la tabla de mensajes (messages_general), nunca
-- para las tablas con precios/markup/proveedor (orders, shortlist), que a
-- propósito se quedan en el poll de 12s para no arriesgar que esa
-- información confidencial se filtre por el canal de Realtime.
--
-- Este único paso es indispensable para que fix66 funcione: hay que agregar
-- la tabla a la publicación de Realtime de Supabase. Sin este paso, el
-- portal simplemente se queda esperando en silencio y sigue funcionando
-- como antes (con el poll de 12s) — no hay riesgo de romper nada si se te
-- olvida correrlo, solo no se pondrá "instantáneo".

alter publication supabase_realtime add table messages_general;
