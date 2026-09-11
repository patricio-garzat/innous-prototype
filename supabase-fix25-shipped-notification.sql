-- El cliente ahora necesita ver el transportista y el número de rastreo de
-- su propio pedido (para que "va en camino" sea algo que de verdad pueda
-- rastrear, no solo un mensaje). No es información confidencial hacia él —
-- es su propio envío — así que se agrega a orders_client_view.
--
-- IMPORTANTE: las columnas nuevas van al FINAL de la lista. Postgres no
-- deja que CREATE OR REPLACE VIEW cambie el nombre/posición de una columna
-- ya existente (ver el error 42P16 de fix24) — insertarlas en medio corre
-- de lugar a las que vienen después y truena.
create or replace view orders_client_view with (security_invoker = true) as
  select project_id, status, customer_price, payment_status, quality_status,
         logistics_destination, estimated_delivery, logistics_documents, quote_number, carrier, tracking
  from orders;

-- No hace falta ninguna función nueva: App.advanceOrderStatus ya llama a
-- innous_send_notification (existente, de fix19) en el momento exacto en
-- que el pedido pasa a "shipped" — nada más faltaba que el cliente pudiera
-- leer esas dos columnas para que el aviso viniera acompañado de datos
-- reales de rastreo.
