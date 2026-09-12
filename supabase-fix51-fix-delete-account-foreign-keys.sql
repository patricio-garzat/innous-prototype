-- BUG: al borrar un proveedor que ya tiene un RFQ en shortlist, un pedido,
-- o mensajes de chat de un proyecto, Postgres rechazaba el borrado con un
-- error de llave foránea (ej. "shortlist_supplier_id_fkey") —
-- innous_delete_account (fix14) intenta borrar la fila de `suppliers`,
-- pero estas tres tablas seguían apuntando a ella.
--
-- fix6 y fix7 ya habían resuelto esto mismo para projects.customer_id,
-- projects.selected_supplier_id, invited_suppliers e supplier_quotes —
-- este archivo solo cubre las 3 tablas que se quedaron fuera entonces:
-- shortlist, orders y messages_project_supplier.
--
-- Mismo criterio que ya usó fix7: shortlist es un artefacto del PROCESO
-- de cotización (las opciones que se le mostraron al cliente, con markup
-- ya aplicado) — la opción que el cliente sí eligió ya quedó copiada de
-- forma independiente en `orders` en el momento en que la eligió (ver
-- client_select_quote), así que borrar su fila en shortlist no borra el
-- pedido real. Por eso lleva cascada, igual que invited_suppliers/
-- supplier_quotes.
--
-- orders y messages_project_supplier sí son el registro real (un pedido
-- de verdad, el historial de chat de un proyecto) — ahí se desvincula al
-- proveedor ya eliminado (se pone en null) en vez de borrar la fila. El
-- portal ya sabe mostrar "Deleted Supplier" en ese caso (ver
-- supplierName() en index.html).

alter table shortlist drop constraint shortlist_supplier_id_fkey;
alter table shortlist add constraint shortlist_supplier_id_fkey
  foreign key (supplier_id) references suppliers(user_id) on delete cascade;

alter table orders alter column supplier_id drop not null;
alter table orders drop constraint orders_supplier_id_fkey;
alter table orders add constraint orders_supplier_id_fkey
  foreign key (supplier_id) references suppliers(user_id) on delete set null;

alter table messages_project_supplier alter column supplier_id drop not null;
alter table messages_project_supplier drop constraint messages_project_supplier_supplier_id_fkey;
alter table messages_project_supplier add constraint messages_project_supplier_supplier_id_fkey
  foreign key (supplier_id) references suppliers(user_id) on delete set null;
