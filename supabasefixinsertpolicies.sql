-- Faltaba: permitir que un usuario recién registrado cree su propio
-- perfil/registro de cliente o proveedor. Sin esto, el registro (signup)
-- fallaría porque las reglas de seguridad bloquearían la inserción.

create policy "usuario crea su propio perfil" on profiles
  for insert with check (user_id = auth.uid());

create policy "cliente crea su propio registro" on customers
  for insert with check (user_id = auth.uid());

create policy "proveedor crea su propio registro" on suppliers
  for insert with check (user_id = auth.uid());
