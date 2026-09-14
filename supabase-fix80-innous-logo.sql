-- fix80: logo de Innous en el chat (en vez del círculo genérico "IN") que
-- ven clientes y proveedores.
--
-- Se guarda en `settings` (el mismo renglón singleton que ya guarda
-- legal_name/address/rfc/phone/email — fix20/fix60), no en el perfil de
-- cada integrante de Innous: es la identidad de la plataforma, la misma
-- para cualquier cliente/proveedor sin importar qué persona de Innous esté
-- conectada en ese momento. Se sube y se recorta igual que cualquier otra
-- foto en la plataforma (el círculo de recorte 1:1 ya existente) y se
-- guarda como imagen embebida directo en esta columna de texto — mismo
-- patrón que ya usan customers.photo_url/suppliers.photo_url/
-- profiles.photo_url, no un archivo aparte en Storage.

alter table settings add column if not exists logo_url text;
