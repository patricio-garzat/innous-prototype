-- fix106: el proveedor deja de poder actualizar el estatus de producción
-- del pedido — decisión explícita del usuario, para que esa
-- responsabilidad sea 100% de INNOUS y no se la carguen a los
-- proveedores. index.html ya deja de mostrarle el botón (supplierNextOrderStatus
-- ahora siempre regresa null) — esto es la parte que de verdad importa:
-- quitarle el permiso a nivel de base de datos, no solo esconder el botón.
--
-- Se borran las DOS políticas que hoy se lo permitían (ninguna se toca a
-- medias, se quitan por completo):
--
-- 1) "proveedor actualiza el estatus de producción" en `orders` (definida
--    en supabase-schema.sql, endurecida después en fix11) — le dejaba
--    cambiar orders.status mientras no fuera ya quality_inspection/
--    shipped/delivered. INNOUS ya tiene su propia política "para todo"
--    en esta tabla (ver "INNOUS ve y controla toda la orden, incluida
--    logística"), así que sigue pudiendo hacer exactamente lo mismo que
--    hacía antes — nada más se quita el acceso del proveedor.
--
-- 2) "proveedor gana pasa el RFQ a in_production" en `projects` (fix10)
--    — le dejaba poner projects.status='in_production' la primera vez
--    que empezaba a producir. Mismo caso: INNOUS ya tiene su propia
--    política de "para todo" en `projects`.
--
-- El proveedor SIGUE viendo el estatus (su política de SELECT en `orders`
-- — "proveedor ve su propia orden (sin logística)" — no se toca), nada
-- más deja de poder cambiarlo.

drop policy if exists "proveedor actualiza el estatus de producción" on orders;
drop policy if exists "proveedor gana pasa el RFQ a in_production" on projects;
