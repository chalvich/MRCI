-- =====================================================================
--  INVENTARIO · Trazabilidad de artículos (compra → envío → venta)
--  Ejecutar UNA vez en Supabase → SQL Editor → New query → Run
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. ACCESO: solo los correos de esta lista pueden ver / editar
-- ---------------------------------------------------------------------
create table if not exists usuarios_permitidos (
  email   text primary key,
  nombre  text,
  creado  timestamptz not null default now()
);

create or replace function es_permitido() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from usuarios_permitidos
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

create or replace function usuario_actual() returns text
language sql stable as $$
  select coalesce(auth.jwt() ->> 'email', 'sistema');
$$;

-- ---------------------------------------------------------------------
-- 2. CATÁLOGOS (se editan desde la app, módulo "Catálogos")
-- ---------------------------------------------------------------------
create table if not exists estatus (
  clave   text primary key,
  nombre  text not null,
  orden   int  not null,
  color   text not null default 'gray'
);

create table if not exists marcas (
  id      bigint generated always as identity primary key,
  nombre  text not null unique
);

create table if not exists canales (
  nombre        text primary key,
  comision_pct  numeric not null default 0,   -- ej. 18  (= 18 %)
  comision_fija numeric not null default 0,   -- ej. 19  (MXN por venta)
  notas         text
);

-- ---------------------------------------------------------------------
-- 3. PAQUETES (envío internacional; un paquete puede traer varios artículos)
-- ---------------------------------------------------------------------
create table if not exists paquetes (
  numero             text primary key,        -- ej. K2603010966
  tipo_envio         text,                    -- EMS, ePacket Light, AIR...
  fecha_envio        date,
  fecha_recibido     date,
  rastreo            text,
  envio_intl_jpy     numeric,
  photo_service_jpy  numeric,
  otros_jpy          numeric,
  total_jpy          numeric,
  total_usd          numeric,
  total_mxn          numeric,                 -- si se llena, se reparte entre sus artículos
  peso_g             numeric,
  dimensiones        text,
  seguro             boolean not null default false,
  inspeccion         boolean not null default false,
  empaque_protector  boolean not null default false,
  notas              text,
  creado_en          timestamptz not null default now(),
  creado_por         text default usuario_actual(),
  actualizado_en     timestamptz not null default now(),
  actualizado_por    text
);

-- ---------------------------------------------------------------------
-- 4. ARTÍCULOS (una fila por pieza)
-- ---------------------------------------------------------------------
create table if not exists articulos (
  id                 text primary key
                     default substr(replace(gen_random_uuid()::text, '-', ''), 1, 8),
  nombre             text not null,
  descripcion        text,
  marca_id           bigint references marcas(id) on delete set null,
  categoria          text,
  color              text,
  talla              text,
  condicion          text,
  pagado_por         text,                    -- CG / CHAVA
  -- compra
  plataforma_compra  text default 'Mercari',
  vendedor           text,
  orden_compra       text,
  fecha_compra       date,
  precio_jpy         numeric,
  precio_usd         numeric,
  pago_mxn           numeric,
  -- envío
  paquete_numero     text references paquetes(numero) on update cascade on delete set null,
  rastreo_correo     text,
  costo_envio_mxn    numeric,                 -- si está vacío se usa el prorrateo del paquete
  impuestos_mxn      numeric default 0,
  otros_costos_mxn   numeric default 0,
  -- venta esperada
  precio_objetivo    numeric,
  canal_objetivo     text references canales(nombre) on update cascade on delete set null,
  -- estado
  estatus            text not null default 'COMPRADO' references estatus(clave) on update cascade,
  ubicacion          text,
  notas              text,
  creado_en          timestamptz not null default now(),
  creado_por         text default usuario_actual(),
  actualizado_en     timestamptz not null default now(),
  actualizado_por    text
);
create index if not exists articulos_paquete_idx on articulos(paquete_numero);
create index if not exists articulos_estatus_idx on articulos(estatus);

-- ---------------------------------------------------------------------
-- 5. CARGOS A TARJETA (compras, envíos, impuestos y gastos personales)
-- ---------------------------------------------------------------------
create table if not exists cargos_tc (
  id               bigint generated always as identity primary key,
  fecha            date,
  articulo_id      text references articulos(id) on update cascade on delete set null,
  concepto         text not null default 'Compra'
                   check (concepto in ('Compra','Envío','Impuestos','Otro')),
  descripcion      text,
  monto_mxn        numeric not null,
  tarjeta          text,
  banco            text,
  estado           text not null default 'PENDIENTE' check (estado in ('PENDIENTE','PAGADO')),
  fecha_pago       date,
  monto_pagado     numeric,
  es_personal      boolean not null default false,
  notas            text,
  creado_en        timestamptz not null default now(),
  creado_por       text default usuario_actual(),
  actualizado_en   timestamptz not null default now(),
  actualizado_por  text
);
create index if not exists cargos_articulo_idx on cargos_tc(articulo_id);

-- ---------------------------------------------------------------------
-- 6. VENTAS (una por artículo)
-- ---------------------------------------------------------------------
create table if not exists ventas (
  id                bigint generated always as identity primary key,
  articulo_id       text not null unique references articulos(id) on update cascade on delete cascade,
  fecha_venta       date default current_date,
  canal             text references canales(nombre) on update cascade on delete set null,
  precio_venta      numeric not null,
  comision_mxn      numeric not null default 0,
  envio_mxn         numeric not null default 0,  -- envío local que pagas tú
  cliente           text,
  telefono          text,
  correo            text,
  destino           text,
  paqueteria        text,
  guia              text,
  fecha_envio       date,
  fecha_deposito    date,
  monto_depositado  numeric,
  cuenta_deposito   text,
  folio             text,
  notas             text,
  creado_en         timestamptz not null default now(),
  creado_por        text default usuario_actual(),
  actualizado_en    timestamptz not null default now(),
  actualizado_por   text
);

-- ---------------------------------------------------------------------
-- 7. FOTOS (los archivos viven en Storage, bucket "fotos")
-- ---------------------------------------------------------------------
create table if not exists fotos (
  id           bigint generated always as identity primary key,
  articulo_id  text not null references articulos(id) on update cascade on delete cascade,
  ruta         text not null unique,           -- ruta dentro del bucket
  tipo         text not null default 'catalogo'
               check (tipo in ('compra','recepcion','catalogo','venta','otro')),
  es_portada   boolean not null default false,
  nota         text,
  creado_en    timestamptz not null default now(),
  creado_por   text default usuario_actual()
);
create index if not exists fotos_articulo_idx on fotos(articulo_id);

-- ---------------------------------------------------------------------
-- 8. HISTORIAL (bitácora inmutable: nadie puede editarla ni borrarla)
-- ---------------------------------------------------------------------
create table if not exists historial (
  id           bigint generated always as identity primary key,
  fecha        timestamptz not null default now(),
  usuario      text,
  tabla        text not null,
  registro_id  text,
  articulo_id  text,
  accion       text not null,                  -- ALTA / CAMBIO / BAJA
  cambios      jsonb
);
create index if not exists historial_articulo_idx on historial(articulo_id, fecha desc);
create index if not exists historial_fecha_idx on historial(fecha desc);

-- ---------------------------------------------------------------------
-- 9. TRIGGERS
-- ---------------------------------------------------------------------
create or replace function sellar_actualizacion() returns trigger
language plpgsql as $$
begin
  new.actualizado_en  := now();
  new.actualizado_por := usuario_actual();
  return new;
end $$;

create or replace function registrar_historial() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_old jsonb; v_new jsonb; v_row jsonb;
  v_cambios jsonb := '{}'::jsonb;
  k text;
  v_pk text := coalesce(tg_argv[0], 'id');
begin
  if tg_op in ('UPDATE','DELETE') then v_old := to_jsonb(old); end if;
  if tg_op in ('INSERT','UPDATE') then v_new := to_jsonb(new); end if;
  v_row := coalesce(v_new, v_old);

  if tg_op = 'UPDATE' then
    for k in select jsonb_object_keys(v_new) loop
      if k not in ('actualizado_en','actualizado_por','creado_en','creado_por')
         and (v_new -> k) is distinct from (v_old -> k) then
        v_cambios := v_cambios || jsonb_build_object(k, jsonb_build_object('de', v_old -> k, 'a', v_new -> k));
      end if;
    end loop;
    if v_cambios = '{}'::jsonb then return new; end if;
  elsif tg_op = 'INSERT' then
    v_cambios := jsonb_strip_nulls(v_new) - 'creado_en' - 'creado_por' - 'actualizado_en' - 'actualizado_por';
  else
    v_cambios := jsonb_strip_nulls(v_old) - 'creado_en' - 'creado_por' - 'actualizado_en' - 'actualizado_por';
  end if;

  insert into historial (usuario, tabla, registro_id, articulo_id, accion, cambios)
  values (
    usuario_actual(), tg_table_name, v_row ->> v_pk,
    case when tg_table_name = 'articulos' then v_row ->> 'id' else v_row ->> 'articulo_id' end,
    case tg_op when 'INSERT' then 'ALTA' when 'UPDATE' then 'CAMBIO' else 'BAJA' end,
    v_cambios
  );
  return coalesce(new, old);
end $$;

-- Al registrar una venta, el artículo pasa a VENDIDO (si aún no estaba más adelante)
create or replace function venta_actualiza_estatus() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update articulos a set estatus = 'VENDIDO'
  where a.id = new.articulo_id
    and (select orden from estatus where clave = a.estatus) < (select orden from estatus where clave = 'VENDIDO');
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['paquetes','articulos','cargos_tc','ventas'] loop
    execute format('drop trigger if exists trg_sello on %I', t);
    execute format('create trigger trg_sello before update on %I for each row execute function sellar_actualizacion()', t);
  end loop;
end $$;

drop trigger if exists trg_hist on articulos;
create trigger trg_hist after insert or update or delete on articulos for each row execute function registrar_historial('id');
drop trigger if exists trg_hist on paquetes;
create trigger trg_hist after insert or update or delete on paquetes  for each row execute function registrar_historial('numero');
drop trigger if exists trg_hist on cargos_tc;
create trigger trg_hist after insert or update or delete on cargos_tc for each row execute function registrar_historial('id');
drop trigger if exists trg_hist on ventas;
create trigger trg_hist after insert or update or delete on ventas    for each row execute function registrar_historial('id');
drop trigger if exists trg_hist on fotos;
create trigger trg_hist after insert or update or delete on fotos     for each row execute function registrar_historial('id');
drop trigger if exists trg_venta_estatus on ventas;
create trigger trg_venta_estatus after insert on ventas for each row execute function venta_actualiza_estatus();

-- ---------------------------------------------------------------------
-- 10. VISTA con costos y utilidad calculados (lo que antes eran fórmulas)
-- ---------------------------------------------------------------------
create or replace view v_articulos with (security_invoker = true) as
with por_paquete as (
  select paquete_numero, count(*) as n
  from articulos where paquete_numero is not null group by paquete_numero
),
base as (
  select
    a.*,
    m.nombre                                  as marca,
    e.nombre                                  as estatus_nombre,
    e.orden                                   as estatus_orden,
    e.color                                   as estatus_color,
    (p.numero is not null and p.total_jpy is not null) as paquete_con_detalle,
    coalesce(a.costo_envio_mxn, round(p.total_mxn / nullif(pp.n, 0), 2)) as envio_mxn_efectivo,
    (a.costo_envio_mxn is null and p.total_mxn is not null)               as envio_prorrateado,
    case when a.precio_jpy > 0 and a.pago_mxn > 0 then round(a.pago_mxn / a.precio_jpy, 4) end as tc_mxn_por_jpy,
    v.id               as venta_id,
    v.fecha_venta,
    v.canal            as canal_venta,
    v.precio_venta,
    v.comision_mxn,
    v.envio_mxn        as envio_venta_mxn,
    v.fecha_deposito,
    v.monto_depositado,
    c.comision_pct     as obj_pct,
    c.comision_fija    as obj_fija,
    (select f.ruta from fotos f where f.articulo_id = a.id order by f.es_portada desc, f.id limit 1) as portada,
    (select count(*) from fotos f where f.articulo_id = a.id)                                      as num_fotos,
    (select coalesce(sum(t.monto_mxn), 0) from cargos_tc t where t.articulo_id = a.id)            as cargos_mxn,
    (select coalesce(sum(t.monto_mxn), 0) from cargos_tc t where t.articulo_id = a.id and t.estado = 'PENDIENTE') as cargos_pendientes_mxn
  from articulos a
  left join marcas m       on m.id = a.marca_id
  left join estatus e      on e.clave = a.estatus
  left join paquetes p     on p.numero = a.paquete_numero
  left join por_paquete pp on pp.paquete_numero = a.paquete_numero
  left join ventas v       on v.articulo_id = a.id
  left join canales c      on c.nombre = a.canal_objetivo
),
costos as (
  select b.*,
    coalesce(b.pago_mxn, 0) + coalesce(b.envio_mxn_efectivo, 0)
      + coalesce(b.impuestos_mxn, 0) + coalesce(b.otros_costos_mxn, 0)          as costo_total,
    b.precio_venta - coalesce(b.comision_mxn, 0) - coalesce(b.envio_venta_mxn, 0) as ingreso_neto,
    b.precio_objetivo - (b.precio_objetivo * coalesce(b.obj_pct, 0) / 100 + coalesce(b.obj_fija, 0)) as ingreso_neto_esperado
  from base b
)
select c.*,
  c.ingreso_neto - c.costo_total                                         as utilidad,
  round((c.ingreso_neto - c.costo_total) / nullif(c.precio_venta, 0), 4)  as margen,
  round(c.ingreso_neto_esperado - c.costo_total, 2)                      as utilidad_esperada,
  round((c.ingreso_neto_esperado - c.costo_total) / nullif(c.precio_objetivo, 0), 4) as margen_esperado,
  (c.fecha_venta - c.fecha_compra)                                        as dias_para_vender,
  (coalesce(c.fecha_venta, current_date) - c.fecha_compra)                as dias_en_inventario
from costos c;

-- ---------------------------------------------------------------------
-- 11. SEGURIDAD (Row Level Security)
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['estatus','marcas','canales','paquetes','articulos','cargos_tc','ventas','fotos'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists acceso_permitido on %I', t);
    execute format('create policy acceso_permitido on %I for all to authenticated using (es_permitido()) with check (es_permitido())', t);
  end loop;
end $$;

-- historial y usuarios: solo lectura desde la app
alter table historial enable row level security;
drop policy if exists lectura on historial;
create policy lectura on historial for select to authenticated using (es_permitido());

alter table usuarios_permitidos enable row level security;
drop policy if exists lectura on usuarios_permitidos;
create policy lectura on usuarios_permitidos for select to authenticated using (es_permitido());

-- ---------------------------------------------------------------------
-- 12. STORAGE: bucket privado para fotos
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('fotos', 'fotos', false)
on conflict (id) do nothing;

drop policy if exists fotos_leer on storage.objects;
drop policy if exists fotos_subir on storage.objects;
drop policy if exists fotos_editar on storage.objects;
drop policy if exists fotos_borrar on storage.objects;
create policy fotos_leer   on storage.objects for select to authenticated using (bucket_id = 'fotos' and public.es_permitido());
create policy fotos_subir  on storage.objects for insert to authenticated with check (bucket_id = 'fotos' and public.es_permitido());
create policy fotos_editar on storage.objects for update to authenticated using (bucket_id = 'fotos' and public.es_permitido());
create policy fotos_borrar on storage.objects for delete to authenticated using (bucket_id = 'fotos' and public.es_permitido());

-- ---------------------------------------------------------------------
-- 13. DATOS BASE
-- ---------------------------------------------------------------------
insert into estatus (clave, nombre, orden, color) values
  ('COMPRADO',   'Comprado',            10, 'sky'),
  ('ALMACEN_JP', 'En almacén Japón',    20, 'purple'),
  ('TRANSITO',   'En tránsito',         30, 'amber'),
  ('RECIBIDO',   'Recibido / revisión', 40, 'teal'),
  ('PUBLICADO',  'Publicado',           50, 'accent'),
  ('APARTADO',   'Apartado',            60, 'rose'),
  ('VENDIDO',    'Vendido',             70, 'green'),
  ('ENTREGADO',  'Entregado',           80, 'green'),
  ('PERSONAL',   'Uso personal / regalo', 90, 'gray'),
  ('CANCELADO',  'Cancelado / devuelto', 95, 'red')
on conflict (clave) do nothing;

insert into canales (nombre, comision_pct, comision_fija, notas) values
  ('GoTrendier', 18, 19, 'Comisión tomada de tu Excel (18 % + $19). Ajusta si cambia.'),
  ('GlosetMX',    0,  0, 'Pon aquí la comisión real.'),
  ('Directo',     0,  0, 'Venta directa / WhatsApp / Instagram')
on conflict (nombre) do nothing;

-- ⚠️ CAMBIA / AGREGA los correos que tendrán acceso
insert into usuarios_permitidos (email, nombre) values
  ('salvador.jimenez.arroyo@gmail.com', 'Chava')
   , ('carlagaba19@gmail.com', 'CG')
on conflict (email) do nothing;
