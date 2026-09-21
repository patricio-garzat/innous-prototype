-- fix113: ahora que innous.com quedó verificado en Resend (DKIM+SPF),
-- los correos de fix112 dejan de mandarse desde el remitente genérico de
-- pruebas (onboarding@resend.dev, causa muy probable de que cayeran en
-- spam) y pasan a mandarse desde notificaciones@innous.com — dominio
-- propio autenticado, mucho mejor entregabilidad.
--
-- Solo redefine innous_send_email (CREATE OR REPLACE, seguro de correr
-- las veces que sea) — no toca nada más de fix112.

create or replace function innous_send_email(p_to text, p_subject text, p_html text)
returns void
language plpgsql
security definer
set search_path = public, vault, net, extensions
as $$
declare
  v_api_key text;
  v_from text := 'INNOUS Portal <notificaciones@innous.com>';
begin
  select decrypted_secret into v_api_key
  from vault.decrypted_secrets
  where name = 'resend_api_key';

  if v_api_key is null or v_api_key = '' or v_api_key = 'PEGA_AQUI_TU_RESEND_API_KEY' then
    raise warning 'innous_send_email: falta configurar la API key de Resend en Vault — correo NO enviado (asunto: %)', p_subject;
    return;
  end if;

  perform net.http_post(
    url := 'https://api.resend.com/emails',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_api_key,
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object(
      'from', v_from,
      'to', jsonb_build_array(p_to),
      'subject', p_subject,
      'html', p_html
    )
  );
end;
$$;
