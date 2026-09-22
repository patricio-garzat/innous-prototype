-- fix129: un admin de INNOUS puede cambiar el correo de inicio de
-- sesión de OTRO compañero de equipo (ej. Andrés, que se quedó atorado
-- con el suyo — ver conversación) — el cambio queda activo de inmediato,
-- sin esperar ninguna confirmación (decisión explícita del usuario, para
-- evitar justo el problema que ya tuvo Andrés: quedarse atorado
-- esperando un correo de confirmación que nunca llegó/nunca se
-- completó). Le llega un aviso a su correo nuevo Y al viejo (buena
-- práctica de seguridad — si el cambio fue un error o algo indebido, el
-- dueño real del correo viejo también se entera), pero es solo
-- informativo, no hay que darle clic a nada.
--
-- No se puede hacer esto con la API normal de Supabase (auth.updateUser
-- solo deja cambiar el correo de la sesión que llama, nunca el de otra
-- cuenta) sin la service_role key — que este proyecto evita a propósito
-- en todas partes. En vez de eso, esta función SECURITY DEFINER corre
-- con la sesión YA AUTENTICADA del admin (nunca la del compañero cuyo
-- correo se está cambiando) y checa is_innous_admin() del lado del
-- servidor — mismo patrón exacto que innous_confirm_new_account (fix127)
-- y create_innous_teammate_profile (fix97).
--
-- Reutiliza innous_send_email/innous_html_escape de fix112 — corre fix112
-- (y fix113 si ya verificaste el dominio) ANTES que este archivo.

create or replace function innous_change_teammate_email(p_user_id uuid, p_new_email text)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_old_email text;
  v_name text;
  v_html text;
begin
  if not is_innous_admin() then
    raise exception 'Not authorized';
  end if;
  if not exists (select 1 from profiles where user_id = p_user_id and role = 'INNOUS') then
    raise exception 'Target is not an INNOUS teammate';
  end if;

  select email into v_old_email from auth.users where id = p_user_id;
  select display_name into v_name from profiles where user_id = p_user_id;

  update auth.users set email = p_new_email, email_confirmed_at = now(), updated_at = now() where id = p_user_id;
  update profiles set email = p_new_email where user_id = p_user_id;

  v_html :=
    '<!doctype html><html><body style="margin:0;padding:0;background:#F7F7F5;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">' ||
    '<div style="max-width:560px;margin:0 auto;padding:32px 16px;">' ||
      '<div style="background:#FFFFFF;border-radius:12px;overflow:hidden;">' ||
        '<div style="height:4px;background:#00A3E0;line-height:4px;font-size:0;">&nbsp;</div>' ||
        '<div style="background:#003865;padding:22px 32px;">' ||
          '<span style="color:#FFFFFF;font-size:19px;font-weight:700;letter-spacing:0.5px;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">INNOUS</span>' ||
        '</div>' ||
        '<div style="padding:32px;">' ||
          '<div style="display:inline-block;background:#E6F6FC;color:#0A7CA6;font-size:11px;font-weight:700;letter-spacing:0.6px;text-transform:uppercase;padding:5px 10px;border-radius:6px;margin-bottom:16px;">Cambio de correo</div>' ||
          '<h1 style="margin:0 0 8px;color:#18181B;font-size:20px;font-weight:700;line-height:1.3;">Tu correo de inicio de sesión cambió</h1>' ||
          '<p style="margin:0 0 24px;color:#52525B;font-size:14px;line-height:1.5;">Hola' || coalesce(' '||innous_html_escape(v_name),'') || ', un administrador de INNOUS actualizó el correo con el que inicias sesión en el portal.</p>' ||
          '<table style="width:100%;border-collapse:collapse;font-size:14px;">' ||
            '<tr><td style="padding:9px 0;color:#71717A;width:130px;vertical-align:top;">Correo anterior</td><td style="padding:9px 0;color:#18181B;">' || coalesce(innous_html_escape(v_old_email),'—') || '</td></tr>' ||
            '<tr><td colspan="2" style="border-top:1px solid #E4E4E7;line-height:0;font-size:0;">&nbsp;</td></tr>' ||
            '<tr><td style="padding:9px 0;color:#71717A;vertical-align:top;">Correo nuevo</td><td style="padding:9px 0;color:#18181B;font-weight:600;">' || innous_html_escape(p_new_email) || '</td></tr>' ||
          '</table>' ||
          '<p style="margin:24px 0 0;color:#A1A1AA;font-size:12px;line-height:1.5;">Ya puedes iniciar sesión con tu correo nuevo. Si no reconoces este cambio, contacta a tu administrador de INNOUS de inmediato.</p>' ||
        '</div>' ||
      '</div>' ||
      '<p style="text-align:center;color:#A1A1AA;font-size:12px;margin-top:20px;">INNOUS · Notificación automática del portal</p>' ||
    '</div>' ||
    '</body></html>';

  perform innous_send_email(p_new_email, 'Tu correo de inicio de sesión en INNOUS cambió', v_html);
  if v_old_email is not null and v_old_email <> p_new_email then
    perform innous_send_email(v_old_email, 'Tu correo de inicio de sesión en INNOUS cambió', v_html);
  end if;
end;
$$;
grant execute on function innous_change_teammate_email(uuid, text) to authenticated;
