-- fix60: el correo de contacto de Innous que aparece en el membrete de la
-- cotización formal y de la Orden de Compra estaba fijo en el código
-- ("sales@innous.com.mx" en la cotización, "compras@innous.com.mx" en la
-- OC) — no había forma de cambiarlo desde Ajustes, a diferencia del
-- teléfono, que ya era editable ahí.
--
-- Se agrega la columna `email` a la tabla `settings` (el mismo renglón
-- singleton que ya guarda legal_name/address/rfc/phone) y ahora ambos
-- documentos usan ese mismo correo editable en vez de tener cada uno el
-- suyo fijo en el código.

alter table settings add column if not exists email text;

update settings set email = 'compras@innous.com.mx' where id = 1 and email is null;
