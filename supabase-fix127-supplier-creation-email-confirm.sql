-- fix127: activar "Confirm email" (fix119/120, para que los CLIENTES
-- confirmen su correo al registrarse solos) rompió sin querer la creación
-- de proveedores desde INNOUS (fix50) y de compañeros de equipo INNOUS
-- (fix97) — "Confirm email" es una sola configuración para todo el
-- proyecto, no distingue quién llama a signUp().
--
-- Lo que pasaba con un proveedor nuevo: App.createSupplierAccount usa la
-- sesión temporal y recién creada del PROVEEDOR (tempClient) para
-- insertar sus propias filas en profiles/suppliers (así evita necesitar
-- la service_role key — ver el comentario de createIsolatedAuthClient).
-- Con "Confirm email" activo, signUp() ya no regresa con sesión hasta que
-- alguien confirme el correo — index.html ya detectaba esto (con un toast
-- de aviso) pero se quedaba ahí: nunca insertaba profiles/suppliers. El
-- correo de confirmación SÍ le llegaba al proveedor (por eso lo veías),
-- pero al picarle al link no había ninguna cuenta que reconocer.
--
-- La corrección real: como es INNOUS quien está creando y vigilando esta
-- cuenta (no un desconocido registrándose solo), no tiene sentido pedirle
-- al proveedor que "confirme" nada — INNOUS ya lo verificó. Esta función
-- deja que la sesión YA AUTENTICADA de INNOUS (nunca la del proveedor
-- nuevo) marque esa cuenta como confirmada de inmediato, para que
-- tempClient pueda entonces iniciar sesión normal y seguir con los
-- inserts de siempre. Mismo patrón exacto que create_innous_teammate_profile
-- (fix97): SECURITY DEFINER, checa el rol de quien LLAMA (INNOUS), nunca
-- del usuario nuevo.

create or replace function innous_confirm_new_account(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if my_role() <> 'INNOUS' then
    raise exception 'Not authorized';
  end if;
  update auth.users set email_confirmed_at = coalesce(email_confirmed_at, now()) where id = p_user_id;
end;
$$;
grant execute on function innous_confirm_new_account(uuid) to authenticated;
