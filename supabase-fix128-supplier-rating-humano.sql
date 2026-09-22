-- fix128: el "Rating" del proveedor (la estrellita que se ve por todos
-- lados — tarjetas de proveedor, comparación de cotizaciones, su ficha)
-- dejaba de ser humano: index.html lo calculaba solo de datos objetivos
-- (% de entregas a tiempo + % de calidad aprobada, ver recalcSupplierMetrics),
-- sin tomar en cuenta lo que el cliente o INNOUS de verdad calificaron
-- después de cada pedido (order_ratings, fix81) — eso solo se mostraba
-- aparte, en la sección "Calificaciones Post-Entrega" de la ficha del
-- proveedor en INNOUS. Ahora el Rating sale ÚNICAMENTE de esas
-- calificaciones humanas (index.html ya trae el cambio correspondiente,
-- ver recalcSupplierRating). % a tiempo / % de calidad siguen siendo sus
-- propios KPIs objetivos aparte, sin tocar.
--
-- Esta migración hace 2 cosas:
--
-- 1) Le da al PROVEEDOR permiso de leer sus propias calificaciones
--    (order_ratings no tenía NINGUNA política para el proveedor — "sin
--    política = sin acceso", a propósito desde fix81, comentario:
--    "Si algún día se decide que el proveedor vea su propio puntaje, se
--    agrega una política de SELECT aparte entonces" — ese día llegó, el
--    proveedor ahora tiene su propia pestaña de "Desempeño" con el
--    desglose completo). Ve tanto lo que calificó el cliente como lo que
--    calificó INNOUS en sus propios pedidos — nunca los de otro proveedor.
--
-- 2) Recalcula suppliers.rating UNA VEZ para que el historial ya
--    existente refleje la nueva fórmula de inmediato, en vez de esperar a
--    que alguien vuelva a calificar algo para que se corrija solo.

create policy "proveedor ve sus propias calificaciones" on order_ratings for select using (
  exists (select 1 from projects p where p.id = order_ratings.project_id and p.selected_supplier_id = auth.uid())
);

update suppliers s
set rating = round(coalesce((
  select avg(v) from (
    select avg((r.ontime_stars + r.quality_stars) / 2.0) as v
    from order_ratings r join projects p on p.id = r.project_id
    where r.rater = 'client' and p.selected_supplier_id = s.user_id
    having count(*) > 0
    union all
    select avg((r.communication_stars + r.ontime_stars + r.quality_stars) / 3.0) as v
    from order_ratings r join projects p on p.id = r.project_id
    where r.rater = 'innous' and p.selected_supplier_id = s.user_id
    having count(*) > 0
  ) x
), 0), 1);
