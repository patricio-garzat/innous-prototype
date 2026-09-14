-- fix79: "permission denied for table profiles" al guardar tu username.
--
-- No es un bug de la app — es que el permiso de UPDATE sobre `profiles` es
-- por COLUMNA (ver supabase-fix4-profile-permissions.sql), a propósito,
-- para que nadie pueda mandar una petición directa y cambiarse su propio
-- `role` a INNOUS. Ese permiso solo cubría (display_name, photo_url):
--
--   grant update (display_name, photo_url) on profiles to authenticated;
--
-- fix78 agregó la columna `username` pero se me olvidó agregarla a este
-- permiso — y cuando a Postgres le falta AUNQUE SEA UNA columna de las que
-- vienen en el UPDATE, rechaza el UPDATE completo con un mensaje genérico
-- ("permission denied for table profiles"), sin decir cuál columna fue.
-- Por eso no se veía obvio cuál era la causa.
--
-- Este GRANT es aditivo — solo agrega `username` a lo que ya se podía
-- editar, no quita ni modifica nada de lo que fix4 ya tenía.

grant update (username) on profiles to authenticated;
