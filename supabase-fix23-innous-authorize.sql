-- Cuando el cliente elige una cotización, el proveedor ganador YA NO se
-- entera de inmediato — se queda como si el RFQ siguiera "en revisión"
-- hasta que Innous, desde su portal, autorice el proyecto explícitamente.
-- Solo hasta ese momento le aparece al proveedor que ganó y que ya puede
-- empezar a trabajar (y se le manda su notificación).
--
-- No hace falta una función nueva: client_select_quote (fix9) no cambia en
-- nada — sigue creando el pedido igual que siempre. Innous ya tiene permiso
-- de UPDATE sobre projects (igual que status, selected_supplier_id, etc.),
-- así que autorizar es un update directo desde la app.
alter table projects add column if not exists innous_authorized_at timestamptz;

-- Pedidos que YA estaban en awarded/in_production/completed antes de este
-- cambio: se marcan como ya autorizados, para no ocultarle de golpe a un
-- proveedor un pedido en el que ya sabía que estaba trabajando.
update projects set innous_authorized_at = now()
where status in ('awarded','in_production','completed') and innous_authorized_at is null;
