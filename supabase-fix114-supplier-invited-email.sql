-- fix114: correo al proveedor cuando INNOUS lo invita a cotizar una RFQ
-- (el mismo momento en que App.sendRfqToSuppliers inserta su fila en
-- invited_suppliers — ver index.html ~línea 8825).
--
-- Reutiliza innous_send_email/innous_html_escape de fix112 — corre fix112
-- (y fix113 si ya verificaste el dominio) ANTES que este archivo.
--
-- Confidencialidad: el proveedor NUNCA ve el nombre/identidad del cliente
-- (ver ROUTES['supplier/rfq'] en index.html — no muestra customerName en
-- ningún lado), así que este correo tampoco lo incluye. Solo lleva lo
-- mismo que ya ve en su propia pantalla de RFQ: especificación, cantidad,
-- material, fecha de entrega y fecha límite para cotizar.
--
-- Seguro de volver a correr (CREATE OR REPLACE / DROP IF EXISTS).

create or replace function fn_notify_supplier_invited()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_html text;
  v_supplier_email text;
  v_project_name text;
  v_process text;
  v_quantity int;
  v_material text;
  v_delivery_date date;
  v_quote_deadline date;
begin
  select email into v_supplier_email from suppliers where user_id = NEW.supplier_id;
  if v_supplier_email is null or v_supplier_email = '' then
    return NEW;
  end if;

  select project_name, process, quantity, material, delivery_date, (created_at + interval '10 days')::date
    into v_project_name, v_process, v_quantity, v_material, v_delivery_date, v_quote_deadline
    from projects where id = NEW.project_id;

  v_html :=
    '<!doctype html><html><body style="margin:0;padding:0;background:#F7F7F5;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">' ||
    '<div style="max-width:560px;margin:0 auto;padding:32px 16px;">' ||
      '<div style="background:#FFFFFF;border-radius:12px;overflow:hidden;">' ||
        '<div style="height:4px;background:#00A3E0;line-height:4px;font-size:0;">&nbsp;</div>' ||
        '<div style="background:#003865;padding:22px 32px;">' ||
          '<span style="color:#FFFFFF;font-size:19px;font-weight:700;letter-spacing:0.5px;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">INNOUS</span>' ||
        '</div>' ||
        '<div style="padding:32px;">' ||
          '<div style="display:inline-block;background:#FFFBEB;color:#B45309;font-size:11px;font-weight:700;letter-spacing:0.6px;text-transform:uppercase;padding:5px 10px;border-radius:6px;margin-bottom:16px;">Pendiente de cotizar</div>' ||
          '<h1 style="margin:0 0 8px;color:#18181B;font-size:20px;font-weight:700;line-height:1.3;">' || innous_html_escape(v_project_name) || '</h1>' ||
          '<p style="margin:0 0 24px;color:#52525B;font-size:14px;line-height:1.5;">INNOUS te invita a cotizar esta solicitud.</p>' ||
          '<table style="width:100%;border-collapse:collapse;font-size:14px;">' ||
            '<tr><td style="padding:9px 0;color:#71717A;width:170px;vertical-align:top;">Folio</td><td style="padding:9px 0;color:#18181B;font-weight:600;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;">' || innous_html_escape(NEW.project_id) || '</td></tr>' ||
            '<tr><td colspan="2" style="border-top:1px solid #E4E4E7;line-height:0;font-size:0;">&nbsp;</td></tr>' ||
            '<tr><td style="padding:9px 0;color:#71717A;vertical-align:top;">Proceso</td><td style="padding:9px 0;color:#18181B;">' || coalesce(innous_html_escape(v_process),'—') || '</td></tr>' ||
            '<tr><td colspan="2" style="border-top:1px solid #E4E4E7;line-height:0;font-size:0;">&nbsp;</td></tr>' ||
            '<tr><td style="padding:9px 0;color:#71717A;vertical-align:top;">Cantidad</td><td style="padding:9px 0;color:#18181B;">' || coalesce(v_quantity::text,'—') || '</td></tr>' ||
            '<tr><td colspan="2" style="border-top:1px solid #E4E4E7;line-height:0;font-size:0;">&nbsp;</td></tr>' ||
            '<tr><td style="padding:9px 0;color:#71717A;vertical-align:top;">Material</td><td style="padding:9px 0;color:#18181B;">' || coalesce(nullif(innous_html_escape(v_material),''),'—') || '</td></tr>' ||
            '<tr><td colspan="2" style="border-top:1px solid #E4E4E7;line-height:0;font-size:0;">&nbsp;</td></tr>' ||
            '<tr><td style="padding:9px 0;color:#71717A;vertical-align:top;">Fecha de entrega</td><td style="padding:9px 0;color:#18181B;">' || coalesce(to_char(v_delivery_date,'DD/MM/YYYY'),'—') || '</td></tr>' ||
            '<tr><td colspan="2" style="border-top:1px solid #E4E4E7;line-height:0;font-size:0;">&nbsp;</td></tr>' ||
            '<tr><td style="padding:9px 0;color:#71717A;vertical-align:top;">Fecha límite para cotizar</td><td style="padding:9px 0;color:#B45309;font-weight:600;">' || coalesce(to_char(v_quote_deadline,'DD/MM/YYYY'),'—') || '</td></tr>' ||
          '</table>' ||
          '<a href="https://portal.innous.com/#/supplier/rfq/' || NEW.project_id || '" style="display:inline-block;margin-top:28px;background-color:#003865;background-image:linear-gradient(90deg,#003865,#0A7CA6);color:#FFFFFF;text-decoration:none;font-size:14px;font-weight:600;padding:12px 24px;border-radius:8px;">Cotizar ahora</a>' ||
        '</div>' ||
      '</div>' ||
      '<p style="text-align:center;color:#A1A1AA;font-size:12px;margin-top:20px;">INNOUS · Notificación automática del portal</p>' ||
    '</div>' ||
    '</body></html>';

  perform innous_send_email(v_supplier_email, 'Nueva RFQ para cotizar: ' || coalesce(v_project_name, NEW.project_id), v_html);
  return NEW;
end;
$$;

drop trigger if exists trg_notify_supplier_invited on invited_suppliers;
create trigger trg_notify_supplier_invited
  after insert on invited_suppliers
  for each row execute function fn_notify_supplier_invited();
