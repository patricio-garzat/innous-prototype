-- Agrega el campo de dirección a Settings (para el PDF de cotización formal
-- que puede descargar el cliente) y actualiza el nombre legal / dirección
-- ya guardados para que coincidan con tu formato real de cotizaciones.
alter table settings add column if not exists address text not null default 'Palma Real No. 115, Fracc. Industrial Las Palmas Santa Catarina, N.L. 66368';

update settings set
  legal_name = 'Grupo Industrial Innous de Mexico S. de R.L. de C.V.',
  address = 'Palma Real No. 115, Fracc. Industrial Las Palmas Santa Catarina, N.L. 66368'
where id = 1 and legal_name = 'INNOUS Sourcing LLC'; -- solo si sigue en el valor de ejemplo original; si ya lo habías editado tú mismo, esto no lo toca
