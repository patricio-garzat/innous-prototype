-- 1) Razón Social (de la Constancia de Situación Fiscal — puede diferir del
--    nombre comercial ya guardado en `name`), Puesto del contacto (mismo
--    concepto que customers.position, para el proveedor), y la ruta del PDF
--    de la Constancia que Innous suba, para poder reabrirla después.
alter table suppliers add column if not exists legal_name text not null default '';
alter table suppliers add column if not exists position text not null default '';
alter table suppliers add column if not exists csf_file_path text;

-- 2) Bucket privado para guardar la Constancia de Situación Fiscal que
--    Innous sube desde el detalle de cada proveedor. Documento fiscal
--    sensible, así que — a diferencia de project-files/chat-files — el
--    acceso queda limitado solo a Innous (ni el propio proveedor lo puede
--    ver/subir por ahora; si más adelante se quiere que el proveedor vea su
--    propia constancia, se agrega una política de select adicional).
insert into storage.buckets (id, name, public, file_size_limit)
values ('account-docs', 'account-docs', false, 10485760) -- 10 MB por archivo
on conflict (id) do update set file_size_limit = 10485760;

-- RLS en storage.objects ya está activado desde fix15 (y de hecho viene
-- activado por default en todo proyecto de Supabase) — volver a activarlo
-- aquí solo pide ser dueño de la tabla, permiso que el editor SQL no tiene
-- sobre storage.objects, y por eso tronaba con "must be owner of table
-- objects". Como ya está activado, esta línea sobraba.

drop policy if exists "account-docs: solo INNOUS ve" on storage.objects;
create policy "account-docs: solo INNOUS ve"
on storage.objects for select
using (bucket_id = 'account-docs' and my_role() = 'INNOUS');

drop policy if exists "account-docs: solo INNOUS sube" on storage.objects;
create policy "account-docs: solo INNOUS sube"
on storage.objects for insert
with check (bucket_id = 'account-docs' and my_role() = 'INNOUS');

drop policy if exists "account-docs: solo INNOUS borra" on storage.objects;
create policy "account-docs: solo INNOUS borra"
on storage.objects for delete
using (bucket_id = 'account-docs' and my_role() = 'INNOUS');
