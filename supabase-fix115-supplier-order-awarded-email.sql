-- fix115: correo al proveedor cuando le cae un pedido de verdad — el
-- momento exacto es App.authorizeProject ("Autorizar y Notificar al
-- Proveedor"), que es la ÚNICA vez que projects.innous_authorized_at pasa
-- de null a una fecha (ver el comentario en index.html junto a
-- authorizeProject: "This is the only place that timestamp ever gets
-- set"). Ya existe una notificación IN-APP en ese mismo punto
-- (sb.rpc('innous_send_notification', ...)) — esto agrega el correo.
--
-- OJO: NO se dispara en client_select_quote (cuando el cliente apenas
-- elige proveedor) — a propósito, porque esa es justo la brecha
-- deliberada que ya existe en el diseño ("Deliberate gap between 'client
-- picked a supplier' and 'supplier finds out'"): el proveedor no debe
-- enterarse hasta que INNOUS autoriza. Dispararlo antes rompería eso.
--
-- Reutiliza innous_send_email/innous_html_escape de fix112 — corre
-- fix112 (y fix113 si ya verificaste el dominio) ANTES que este archivo.
--
-- Confidencialidad: solo se manda lo que orders_supplier_view ya le deja
-- ver al proveedor (supplier_cost, no customer_price/markup_pct; nada de
-- logistics_*, que es solo de INNOUS). Nada del cliente tampoco.
--
-- Seguro de volver a correr (CREATE OR REPLACE / DROP IF EXISTS).

create or replace function fn_notify_supplier_order_awarded()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_html text;
  v_supplier_email text;
  v_po_number text;
  v_supplier_cost numeric;
  v_supplier_cost_mxn numeric;
  v_estimated_delivery date;
  v_po_delivery_location text;
  v_po_payment_terms text;
begin
  if NEW.innous_authorized_at is null or OLD.innous_authorized_at is not null or NEW.selected_supplier_id is null then
    return NEW;
  end if;

  select email into v_supplier_email from suppliers where user_id = NEW.selected_supplier_id;
  if v_supplier_email is null or v_supplier_email = '' then
    return NEW;
  end if;

  select po_number, supplier_cost, supplier_cost_mxn, estimated_delivery, po_delivery_location, po_payment_terms
    into v_po_number, v_supplier_cost, v_supplier_cost_mxn, v_estimated_delivery, v_po_delivery_location, v_po_payment_terms
    from orders where project_id = NEW.id;

  v_html :=
    '<!doctype html><html><body style="margin:0;padding:0;background:#F7F7F5;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">' ||
    '<div style="max-width:560px;margin:0 auto;padding:32px 16px;">' ||
      '<div style="background:#FFFFFF;border-radius:12px;overflow:hidden;">' ||
        '<div style="height:4px;background:#00A3E0;line-height:4px;font-size:0;">&nbsp;</div>' ||
        '<div style="background:#003865;padding:22px 32px;">' ||
          '<span style="color:#FFFFFF;font-size:19px;font-weight:700;letter-spacing:0.5px;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">INNOUS</span>' ||
        '</div>' ||
        '<div style="padding:32px;">' ||
          '<div style="display:inline-block;background:#F0FDF4;color:#15803D;font-size:11px;font-weight:700;letter-spacing:0.6px;text-transform:uppercase;padding:5px 10px;border-radius:6px;margin-bottom:16px;">Pedido confirmado</div>' ||
          '<h1 style="margin:0 0 8px;color:#18181B;font-size:20px;font-weight:700;line-height:1.3;">' || innous_html_escape(NEW.project_name) || '</h1>' ||
          '<p style="margin:0 0 24px;color:#52525B;font-size:14px;line-height:1.5;">INNOUS autorizó tu cotización — ya puedes empezar a trabajar en este pedido.</p>' ||
          '<table style="width:100%;border-collapse:collapse;font-size:14px;">' ||
            '<tr><td style="padding:9px 0;color:#71717A;width:170px;vertical-align:top;">Orden de compra</td><td style="padding:9px 0;color:#18181B;font-weight:600;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;">' || coalesce(innous_html_escape(v_po_number), innous_html_escape(NEW.id)) || '</td></tr>' ||
            '<tr><td colspan="2" style="border-top:1px solid #E4E4E7;line-height:0;font-size:0;">&nbsp;</td></tr>' ||
            '<tr><td style="padding:9px 0;color:#71717A;vertical-align:top;">Cantidad</td><td style="padding:9px 0;color:#18181B;">' || coalesce(NEW.quantity::text,'—') || '</td></tr>' ||
            '<tr><td colspan="2" style="border-top:1px solid #E4E4E7;line-height:0;font-size:0;">&nbsp;</td></tr>' ||
            '<tr><td style="padding:9px 0;color:#71717A;vertical-align:top;">Material</td><td style="padding:9px 0;color:#18181B;">' || coalesce(nullif(innous_html_escape(NEW.material),''),'—') || '</td></tr>' ||
            '<tr><td colspan="2" style="border-top:1px solid #E4E4E7;line-height:0;font-size:0;">&nbsp;</td></tr>' ||
            '<tr><td style="padding:9px 0;color:#71717A;vertical-align:top;">Costo acordado</td><td style="padding:9px 0;color:#18181B;font-weight:600;">' || coalesce('$'||to_char(coalesce(v_supplier_cost_mxn,v_supplier_cost),'FM999,999,990.00')||' MXN','—') || '</td></tr>' ||
            '<tr><td colspan="2" style="border-top:1px solid #E4E4E7;line-height:0;font-size:0;">&nbsp;</td></tr>' ||
            '<tr><td style="padding:9px 0;color:#71717A;vertical-align:top;">Fecha estimada de entrega</td><td style="padding:9px 0;color:#18181B;">' || coalesce(to_char(v_estimated_delivery,'DD/MM/YYYY'),'—') || '</td></tr>' ||
            '<tr><td colspan="2" style="border-top:1px solid #E4E4E7;line-height:0;font-size:0;">&nbsp;</td></tr>' ||
            '<tr><td style="padding:9px 0;color:#71717A;vertical-align:top;">Lugar de entrega</td><td style="padding:9px 0;color:#18181B;">' || coalesce(nullif(innous_html_escape(v_po_delivery_location),''),'—') || '</td></tr>' ||
            '<tr><td colspan="2" style="border-top:1px solid #E4E4E7;line-height:0;font-size:0;">&nbsp;</td></tr>' ||
            '<tr><td style="padding:9px 0;color:#71717A;vertical-align:top;">Condiciones de pago</td><td style="padding:9px 0;color:#18181B;">' || coalesce(nullif(innous_html_escape(v_po_payment_terms),''),'—') || '</td></tr>' ||
          '</table>' ||
          '<a href="https://portal.innous.com/#/supplier/order/' || NEW.id || '" style="display:inline-block;margin-top:28px;background-color:#003865;background-image:linear-gradient(90deg,#003865,#0A7CA6);color:#FFFFFF;text-decoration:none;font-size:14px;font-weight:600;padding:12px 24px;border-radius:8px;">Ver pedido y descargar Orden de Compra</a>' ||
        '</div>' ||
      '</div>' ||
      '<p style="text-align:center;color:#A1A1AA;font-size:12px;margin-top:20px;">INNOUS · Notificación automática del portal</p>' ||
    '</div>' ||
    '</body></html>';

  perform innous_send_email(v_supplier_email, 'Pedido confirmado: ' || NEW.project_name || ' (' || coalesce(v_po_number, NEW.id) || ')', v_html);
  return NEW;
end;
$$;

drop trigger if exists trg_notify_supplier_order_awarded on projects;
create trigger trg_notify_supplier_order_awarded
  after update on projects
  for each row execute function fn_notify_supplier_order_awarded();
