-- fix99: "permission denied for table profiles" al cambiar el nivel de
-- acceso (admin/viewer) de un compañero de INNOUS.
--
-- Mismo bug exacto que fix79 con `username`: el permiso de UPDATE sobre
-- `profiles` es por COLUMNA a propósito (ver supabase-fix4-profile-
-- permissions.sql), para que nadie pueda mandar una petición directa y
-- cambiarse su propio `role` a INNOUS. fix97 agregó la columna
-- `innous_access` pero se me olvidó agregarla a este permiso — y cuando a
-- Postgres le falta AUNQUE SEA UNA columna de las que vienen en el
-- UPDATE, rechaza el UPDATE completo con ese mensaje genérico, sin decir
-- cuál columna fue.
--
-- Este GRANT es aditivo — solo agrega `innous_access` a lo que ya se
-- podía editar, no quita ni modifica nada de lo que fix4/fix78/fix79 ya
-- tenían. App.changeTeammateAccess() sigue estando protegido por la
-- política RESTRICTIVE de fix97 (solo un admin puede tocar el perfil de
-- alguien más) — este GRANT solo destraba la columna a nivel de permisos
-- de tabla, la autorización real sigue siendo la política RLS.

grant update (innous_access) on profiles to authenticated;
