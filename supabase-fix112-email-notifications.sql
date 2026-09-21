-- fix112: correos automáticos a patricio@innous.com cuando (1) se registra
-- un cliente nuevo y (2) un cliente manda una RFQ nueva.
--
-- Cómo funciona (sin Edge Function, sin tocar index.html, sin que Claude
-- vea nunca tu API key de Resend):
--
--   Se usa `pg_net` (ya viene disponible en todo proyecto Supabase) para
--   que la BASE DE DATOS misma haga la llamada HTTP a la API de Resend
--   (resend.com — servicio de envío de correo, plan gratis hasta 3,000
--   correos/mes) cada vez que se inserta una fila nueva en `customers` o
--   en `projects`. Un TRIGGER dispara una función SECURITY DEFINER (mismo
--   patrón que ya usa create_innous_teammate_profile) que arma el correo
--   en HTML con los mismos colores de marca del portal y lo manda.
--
--   Tu API key de Resend se guarda cifrada en Supabase Vault (nunca queda
--   en texto plano en ninguna tabla), y este archivo es el único lugar
--   donde la pegas — yo (Claude) nunca la veo.
--
-- ANTES DE CORRER ESTO:
--
--   1) Crea una cuenta gratis en https://resend.com con patricio@innous.com
--   2) Ve a "API Keys" → crea una nueva → cópiala (empieza con "re_")
--   3) Abajo, en la línea que dice PEGA_AQUI_TU_RESEND_API_KEY, bórrala y
--      pega tu key real (entre las comillas simples, tal cual)
--   4) (Opcional pero recomendado) Verifica el dominio innous.com en
--      Resend → Domains → Add Domain, y agrega los registros DNS que te
--      dé (parecido a lo que ya hiciste para Google Workspace). Mientras
--      NO lo verifiques, el correo se manda desde una dirección genérica
--      de pruebas de Resend, y solo llega bien a la cuenta con la que te
--      registraste en Resend — como te registraste con patricio@innous.com,
--      igual te va a llegar. Ya que verifiques el dominio, avísame y te
--      doy el cambio de una línea para que se vea "notificaciones@innous.com".
--
-- Se puede volver a correr este archivo completo sin problema (todo es
-- CREATE OR REPLACE / DROP IF EXISTS) — por ejemplo si necesitas rotar tu
-- API key más adelante, solo pega la nueva arriba y vuelve a correrlo.

create extension if not exists pg_net;
-- Si esta línea da error de permisos: ve al Dashboard de Supabase →
-- Database → Extensions → busca "pg_net" → actívala ahí, y vuelve a
-- correr el resto del archivo.

do $$
begin
  if exists (select 1 from vault.secrets where name = 'resend_api_key') then
    perform vault.update_secret(
      (select id from vault.secrets where name = 'resend_api_key'),
      'PEGA_AQUI_TU_RESEND_API_KEY'
    );
  else
    perform vault.create_secret(
      'PEGA_AQUI_TU_RESEND_API_KEY',
      'resend_api_key',
      'API key de Resend para los correos automáticos del portal INNOUS'
    );
  end if;
end $$;

-- Escapa texto que viene de formularios (nombre de empresa, contacto,
-- etc.) antes de meterlo en el HTML del correo, para que un nombre con
-- "<", "&" o comillas nunca rompa el formato del correo.
create or replace function innous_html_escape(txt text)
returns text
language sql
immutable
as $$
  select coalesce(
    replace(replace(replace(replace(replace(txt, '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;'), '''', '&#39;'),
  '');
$$;

-- Función compartida: arma la llamada a la API de Resend. Las dos
-- funciones de abajo (cliente nuevo / RFQ nueva) solo construyen el HTML
-- y le llaman a esta.
create or replace function innous_send_email(p_to text, p_subject text, p_html text)
returns void
language plpgsql
security definer
set search_path = public, vault, net, extensions
as $$
declare
  v_api_key text;
  -- Remitente mientras el dominio innous.com no esté verificado en Resend.
  -- Cuando lo verifiques, cambia esta línea a:
  --   v_from text := 'INNOUS Portal <notificaciones@innous.com>';
  v_from text := 'INNOUS Portal <onboarding@resend.dev>';
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

/* ---------- Cliente nuevo registrado ---------- */
create or replace function fn_notify_new_client()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_html text;
begin
  v_html :=
    '<!doctype html><html><body style="margin:0;padding:0;background:#F7F7F5;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">' ||
    '<div style="max-width:560px;margin:0 auto;padding:32px 16px;">' ||
      '<div style="background:#FFFFFF;border-radius:12px;overflow:hidden;">' ||
        '<div style="height:4px;background:#00A3E0;line-height:4px;font-size:0;">&nbsp;</div>' ||
        '<div style="background:#003865;padding:22px 32px;">' ||
          '<span style="color:#FFFFFF;font-size:19px;font-weight:700;letter-spacing:0.5px;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">INNOUS</span>' ||
        '</div>' ||
        '<div style="padding:32px;">' ||
          '<div style="display:inline-block;background:#E6F6FC;color:#0A7CA6;font-size:11px;font-weight:700;letter-spacing:0.6px;text-transform:uppercase;padding:5px 10px;border-radius:6px;margin-bottom:16px;">Nuevo cliente</div>' ||
          '<h1 style="margin:0 0 8px;color:#18181B;font-size:20px;font-weight:700;line-height:1.3;">' || innous_html_escape(NEW.company) || '</h1>' ||
          '<p style="margin:0 0 24px;color:#52525B;font-size:14px;line-height:1.5;">Se acaba de registrar un cliente nuevo en el portal.</p>' ||
          '<table style="width:100%;border-collapse:collapse;font-size:14px;">' ||
            '<tr><td style="padding:9px 0;color:#71717A;width:130px;vertical-align:top;">Contacto</td><td style="padding:9px 0;color:#18181B;font-weight:600;">' || innous_html_escape(NEW.contact) || '</td></tr>' ||
            '<tr><td colspan="2" style="border-top:1px solid #E4E4E7;line-height:0;font-size:0;">&nbsp;</td></tr>' ||
            '<tr><td style="padding:9px 0;color:#71717A;vertical-align:top;">Correo</td><td style="padding:9px 0;color:#18181B;">' || innous_html_escape(NEW.email) || '</td></tr>' ||
            '<tr><td colspan="2" style="border-top:1px solid #E4E4E7;line-height:0;font-size:0;">&nbsp;</td></tr>' ||
            '<tr><td style="padding:9px 0;color:#71717A;vertical-align:top;">Teléfono</td><td style="padding:9px 0;color:#18181B;">' || coalesce(nullif(innous_html_escape(NEW.phone),''),'—') || '</td></tr>' ||
            '<tr><td colspan="2" style="border-top:1px solid #E4E4E7;line-height:0;font-size:0;">&nbsp;</td></tr>' ||
            '<tr><td style="padding:9px 0;color:#71717A;vertical-align:top;">Ciudad</td><td style="padding:9px 0;color:#18181B;">' || coalesce(nullif(innous_html_escape(NEW.city),''),'—') || '</td></tr>' ||
            '<tr><td colspan="2" style="border-top:1px solid #E4E4E7;line-height:0;font-size:0;">&nbsp;</td></tr>' ||
            '<tr><td style="padding:9px 0;color:#71717A;vertical-align:top;">Industria</td><td style="padding:9px 0;color:#18181B;">' || coalesce(nullif(innous_html_escape(NEW.industry),''),'—') || '</td></tr>' ||
          '</table>' ||
          '<a href="https://portal.innous.com/#/innous/customer/' || NEW.user_id::text || '" style="display:inline-block;margin-top:28px;background-color:#003865;background-image:linear-gradient(90deg,#003865,#0A7CA6);color:#FFFFFF;text-decoration:none;font-size:14px;font-weight:600;padding:12px 24px;border-radius:8px;">Ver cliente en el portal</a>' ||
        '</div>' ||
      '</div>' ||
      '<p style="text-align:center;color:#A1A1AA;font-size:12px;margin-top:20px;">INNOUS · Notificación automática del portal</p>' ||
    '</div>' ||
    '</body></html>';

  perform innous_send_email('patricio@innous.com', 'Nuevo cliente registrado: ' || NEW.company, v_html);
  return NEW;
end;
$$;

drop trigger if exists trg_notify_new_client on customers;
create trigger trg_notify_new_client
  after insert on customers
  for each row execute function fn_notify_new_client();

/* ---------- RFQ nueva ---------- */
create or replace function fn_notify_new_rfq()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_html text;
  v_company text;
begin
  select company into v_company from customers where user_id = NEW.customer_id;

  v_html :=
    '<!doctype html><html><body style="margin:0;padding:0;background:#F7F7F5;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">' ||
    '<div style="max-width:560px;margin:0 auto;padding:32px 16px;">' ||
      '<div style="background:#FFFFFF;border-radius:12px;overflow:hidden;">' ||
        '<div style="height:4px;background:#00A3E0;line-height:4px;font-size:0;">&nbsp;</div>' ||
        '<div style="background:#003865;padding:22px 32px;">' ||
          '<span style="color:#FFFFFF;font-size:19px;font-weight:700;letter-spacing:0.5px;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">INNOUS</span>' ||
        '</div>' ||
        '<div style="padding:32px;">' ||
          '<div style="display:inline-block;background:#F1E9FB;color:#6D28D9;font-size:11px;font-weight:700;letter-spacing:0.6px;text-transform:uppercase;padding:5px 10px;border-radius:6px;margin-bottom:16px;">RFQ nueva</div>' ||
          '<h1 style="margin:0 0 8px;color:#18181B;font-size:20px;font-weight:700;line-height:1.3;">' || innous_html_escape(NEW.project_name) || '</h1>' ||
          '<p style="margin:0 0 24px;color:#52525B;font-size:14px;line-height:1.5;">' || coalesce(innous_html_escape(v_company),'Un cliente') || ' acaba de mandar una solicitud de cotización.</p>' ||
          '<table style="width:100%;border-collapse:collapse;font-size:14px;">' ||
            '<tr><td style="padding:9px 0;color:#71717A;width:150px;vertical-align:top;">Folio</td><td style="padding:9px 0;color:#18181B;font-weight:600;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;">' || innous_html_escape(NEW.id) || '</td></tr>' ||
            '<tr><td colspan="2" style="border-top:1px solid #E4E4E7;line-height:0;font-size:0;">&nbsp;</td></tr>' ||
            '<tr><td style="padding:9px 0;color:#71717A;vertical-align:top;">Cliente</td><td style="padding:9px 0;color:#18181B;">' || coalesce(innous_html_escape(v_company),'—') || '</td></tr>' ||
            '<tr><td colspan="2" style="border-top:1px solid #E4E4E7;line-height:0;font-size:0;">&nbsp;</td></tr>' ||
            '<tr><td style="padding:9px 0;color:#71717A;vertical-align:top;">Proceso</td><td style="padding:9px 0;color:#18181B;">' || innous_html_escape(NEW.process) || '</td></tr>' ||
            '<tr><td colspan="2" style="border-top:1px solid #E4E4E7;line-height:0;font-size:0;">&nbsp;</td></tr>' ||
            '<tr><td style="padding:9px 0;color:#71717A;vertical-align:top;">Cantidad</td><td style="padding:9px 0;color:#18181B;">' || NEW.quantity::text || '</td></tr>' ||
            '<tr><td colspan="2" style="border-top:1px solid #E4E4E7;line-height:0;font-size:0;">&nbsp;</td></tr>' ||
            '<tr><td style="padding:9px 0;color:#71717A;vertical-align:top;">Material</td><td style="padding:9px 0;color:#18181B;">' || coalesce(nullif(innous_html_escape(NEW.material),''),'—') || '</td></tr>' ||
            '<tr><td colspan="2" style="border-top:1px solid #E4E4E7;line-height:0;font-size:0;">&nbsp;</td></tr>' ||
            '<tr><td style="padding:9px 0;color:#71717A;vertical-align:top;">Fecha de entrega</td><td style="padding:9px 0;color:#18181B;">' || coalesce(to_char(NEW.delivery_date,'DD/MM/YYYY'),'—') || '</td></tr>' ||
            '<tr><td colspan="2" style="border-top:1px solid #E4E4E7;line-height:0;font-size:0;">&nbsp;</td></tr>' ||
            '<tr><td style="padding:9px 0;color:#71717A;vertical-align:top;">Lugar de entrega</td><td style="padding:9px 0;color:#18181B;">' || coalesce(nullif(innous_html_escape(NEW.delivery_location),''),'—') || '</td></tr>' ||
          '</table>' ||
          case when NEW.description is not null and NEW.description <> '' then
            '<div style="margin-top:20px;background:#FAFAFA;border:1px solid #E4E4E7;border-radius:8px;padding:14px 16px;">' ||
              '<div style="color:#71717A;font-size:11px;font-weight:700;letter-spacing:0.4px;text-transform:uppercase;margin-bottom:6px;">Descripción</div>' ||
              '<div style="color:#18181B;font-size:13px;line-height:1.5;">' || innous_html_escape(NEW.description) || '</div>' ||
            '</div>'
          else '' end ||
          '<a href="https://portal.innous.com/#/innous/rfq/' || NEW.id || '" style="display:inline-block;margin-top:28px;background-color:#003865;background-image:linear-gradient(90deg,#003865,#0A7CA6);color:#FFFFFF;text-decoration:none;font-size:14px;font-weight:600;padding:12px 24px;border-radius:8px;">Ver RFQ en el portal</a>' ||
        '</div>' ||
      '</div>' ||
      '<p style="text-align:center;color:#A1A1AA;font-size:12px;margin-top:20px;">INNOUS · Notificación automática del portal</p>' ||
    '</div>' ||
    '</body></html>';

  perform innous_send_email('patricio@innous.com', 'Nueva RFQ: ' || NEW.project_name || ' (' || NEW.id || ')', v_html);
  return NEW;
end;
$$;

drop trigger if exists trg_notify_new_rfq on projects;
create trigger trg_notify_new_rfq
  after insert on projects
  for each row execute function fn_notify_new_rfq();
