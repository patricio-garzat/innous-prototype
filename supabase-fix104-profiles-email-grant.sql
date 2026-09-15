-- fix104: permite que cada quien edite su propio correo mostrado en
-- "Equipo INNOUS" (profiles.email) — mismo patrón exacto que fix79/fix99
-- con username/innous_access: el UPDATE de `profiles` es por columna a
-- propósito, y fix97 agregó la columna `email` pero nunca la agregó a
-- este permiso. Sin esto, App.saveAccount tronaría con "permission denied
-- for table profiles" en cuanto alguien intentara cambiar su correo desde
-- Configuración de Cuenta.
--
-- Aditivo — no quita ni modifica nada de lo que fix4/fix78/fix79/fix99 ya
-- permitían.

grant update (email) on profiles to authenticated;
