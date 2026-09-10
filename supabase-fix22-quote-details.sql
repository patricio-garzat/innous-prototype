-- Campos de la "cotización formal" que Innous debe llenar a mano antes de
-- que el cliente la descargue (nombre y correo del vendedor, condiciones de
-- pago, tiempo de entrega) — nunca se toman de lo que el proveedor haya
-- puesto en su propia cotización. Se editan desde la nueva sección "Formal
-- Quote Details" en la vista del RFQ dentro del portal de Innous.
--
-- No hace falta tocar RLS: `projects` ya se lee completa (select '*') por
-- cualquier rol que pueda ver esa fila, y solo Innous tiene permiso de
-- UPDATE sobre projects (igual que status, selected_supplier_id, etc.) —
-- estas columnas nuevas heredan exactamente esas mismas reglas.
alter table projects add column if not exists quote_salesperson_name text;
alter table projects add column if not exists quote_salesperson_email text;
alter table projects add column if not exists quote_payment_terms text;
alter table projects add column if not exists quote_delivery_days int;
