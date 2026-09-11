-- El folio del RFQ (el "id" del proyecto) ahora es un consecutivo limpio:
-- RFQ0000, RFQ0001, RFQ0002... en vez del esquema anterior
-- ('IN-2026-00XXX', armado con un número semi-aleatorio calculado en el
-- navegador del cliente — lo cual además podía, en teoría, chocar entre dos
-- clientes distintos enviando un RFQ casi al mismo tiempo, porque cada quien
-- lo calculaba con su propio conteo local de proyectos).
--
-- Con una secuencia de Postgres como DEFAULT de la columna, el número lo
-- asigna la base de datos de forma atómica — nunca se puede repetir, sin
-- importar cuántos clientes envíen un RFQ al mismo tiempo.
--
-- Esto es solo para RFQs NUEVOS de aquí en adelante — los folios ya
-- existentes ('IN-2026-...') no se tocan, porque son la llave primaria de
-- projects y cambiarla ahora tendría que actualizar en cascada shortlist,
-- supplier_quotes, orders, invited_suppliers y order_milestones. No vale la
-- pena el riesgo solo por renumerar folios que el cliente y el proveedor ya
-- conocen y ya usan para dar seguimiento a su pedido.
create sequence if not exists rfq_seq start with 0 minvalue 0;
alter table projects alter column id set default ('RFQ'||lpad(nextval('rfq_seq')::text, 4, '0'));
