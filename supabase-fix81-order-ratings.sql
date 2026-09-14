-- fix81: calificación post-entrega — el cliente califica la entrega
-- (tiempo, calidad) sin saber quién es el proveedor, e INNOUS por su
-- lado califica al proveedor mismo (comunicación, tiempos, calidad) para
-- su propio historial interno. Un renglón por pedido y por quién califica.
--
-- Se guarda separado de `orders` (que ya tiene su propio sistema de
-- indicadores 100% automático — a tiempo/calidad calculados de la fecha de
-- entrega y del estatus de inspección, ver recalcSupplierMetrics en
-- index.html) porque esto es la parte humana/subjetiva, no reemplaza esos
-- números, los complementa.
--
-- rater='client': solo llena ontime_stars/quality_stars — el cliente nunca
-- sabe quién es el proveedor, así que no tiene nada que decir sobre
-- "comunicación" de alguien que no conoce.
-- rater='innous': llena las tres — communication_stars/ontime_stars/
-- quality_stars — su propia evaluación interna del proveedor.
--
-- unique(project_id, rater): como máximo un renglón de cada quien por
-- pedido — calificar de nuevo actualiza el mismo renglón (upsert desde la
-- app), no crea uno nuevo. Así se puede cambiar de opinión sin líos.

create table if not exists order_ratings (
  id uuid primary key default gen_random_uuid(),
  project_id text not null references projects(id) on delete cascade,
  rater text not null check (rater in ('client','innous')),
  ontime_stars smallint check (ontime_stars between 1 and 5),
  quality_stars smallint check (quality_stars between 1 and 5),
  communication_stars smallint check (communication_stars between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id, rater)
);

alter table order_ratings enable row level security;

-- El cliente ve/escribe/actualiza ÚNICAMENTE su propia calificación
-- (rater='client') y solo en un pedido de un RFQ suyo — mismo patrón que
-- ya usan las políticas de `shortlist`/`orders` (projects.customer_id =
-- auth.uid()).
create policy "cliente ve su propia calificación" on order_ratings for select using (
  rater = 'client' and exists (select 1 from projects p where p.id = order_ratings.project_id and p.customer_id = auth.uid())
);
create policy "cliente escribe su propia calificación" on order_ratings for insert with check (
  rater = 'client' and exists (select 1 from projects p where p.id = order_ratings.project_id and p.customer_id = auth.uid())
);
create policy "cliente actualiza su propia calificación" on order_ratings for update using (
  rater = 'client' and exists (select 1 from projects p where p.id = order_ratings.project_id and p.customer_id = auth.uid())
);

-- INNOUS ve y administra todas las calificaciones (las suyas propias para
-- escribirlas, y las de los clientes para poder verlas también).
create policy "INNOUS administra todas las calificaciones" on order_ratings for all using (my_role() = 'INNOUS');

-- El proveedor NO tiene ninguna política aquí — por diseño, sin política =
-- sin acceso, igual que customers. Si algún día se decide que el proveedor
-- vea su propio puntaje, se agrega una política de SELECT aparte entonces.
