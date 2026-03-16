begin;

-- =========================================================
-- 1) EXTENSIONES
-- =========================================================
create extension if not exists pgcrypto;
create extension if not exists pg_trgm;

-- =========================================================
-- 2) FUNCIONES BASE
-- =========================================================

create or replace function public.normalize_text(input text)
returns text
language sql
immutable
parallel safe
as $$
  select trim(
    regexp_replace(
      regexp_replace(
        translate(
          lower(coalesce(input, '')),
          'áàäâãåéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÅÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ',
          'aaaaaaeeeeiiiiooooouuuuncaaaaaaeeeeiiiiooooouuuunc'
        ),
        '[^a-z0-9 ]+',
        ' ',
        'g'
      ),
      '\s+',
      ' ',
      'g'
    )
  );
$$;

create or replace function public.haversine_m(
  lat1 double precision,
  lon1 double precision,
  lat2 double precision,
  lon2 double precision
)
returns double precision
language sql
immutable
parallel safe
as $$
  select 2 * 6371000 * asin(
    sqrt(
      power(sin(radians((lat2 - lat1) / 2)), 2)
      + cos(radians(lat1)) * cos(radians(lat2))
      * power(sin(radians((lon2 - lon1) / 2)), 2)
    )
  );
$$;

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- =========================================================
-- 3) TABLAS PRINCIPALES
-- =========================================================

-- -------------------------
-- 3.1 Líneas
-- -------------------------
create table if not exists public.lineas (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  nombre text not null,
  nombre_norm text generated always as (public.normalize_text(nombre)) stored,
  modo text not null check (modo in ('metro', 'teleferico', 'omsa')),
  color_hex text,
  descripcion text,
  orden_visual integer,
  activa boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- -------------------------
-- 3.2 Estaciones Metro / Teleférico
-- -------------------------
create table if not exists public.estaciones (
  id uuid primary key default gen_random_uuid(),
  linea_id uuid not null references public.lineas(id) on delete cascade,
  codigo text not null unique,
  nombre text not null,
  nombre_norm text generated always as (public.normalize_text(nombre)) stored,
  orden_en_linea integer not null,
  es_terminal boolean not null default false,
  es_transbordo boolean not null default false,
  lat double precision not null,
  lon double precision not null,
  municipio text default 'Santo Domingo',
  sector text,
  direccion_referencia text,
  activa boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (linea_id, orden_en_linea)
);

create table if not exists public.estaciones_aliases (
  id uuid primary key default gen_random_uuid(),
  estacion_id uuid not null references public.estaciones(id) on delete cascade,
  alias text not null,
  alias_norm text generated always as (public.normalize_text(alias)) stored,
  es_principal boolean not null default false,
  created_at timestamptz not null default now(),
  unique (estacion_id, alias_norm)
);

-- -------------------------
-- 3.3 Rutas y Paradas OMSA
-- -------------------------
create table if not exists public.rutas_omsa (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  nombre text not null,
  nombre_norm text generated always as (public.normalize_text(nombre)) stored,
  descripcion text,
  sentido text check (sentido in ('ida', 'vuelta', 'circular', 'ambos')),
  linea_id uuid references public.lineas(id) on delete set null,
  activa boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.paradas_omsa (
  id uuid primary key default gen_random_uuid(),
  codigo text unique,
  nombre text not null,
  nombre_norm text generated always as (public.normalize_text(nombre)) stored,
  lat double precision not null,
  lon double precision not null,
  municipio text default 'Santo Domingo',
  sector text,
  direccion_referencia text,
  techada boolean not null default false,
  activa boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.paradas_omsa_aliases (
  id uuid primary key default gen_random_uuid(),
  parada_omsa_id uuid not null references public.paradas_omsa(id) on delete cascade,
  alias text not null,
  alias_norm text generated always as (public.normalize_text(alias)) stored,
  es_principal boolean not null default false,
  created_at timestamptz not null default now(),
  unique (parada_omsa_id, alias_norm)
);

create table if not exists public.rutas_omsa_paradas (
  id uuid primary key default gen_random_uuid(),
  ruta_omsa_id uuid not null references public.rutas_omsa(id) on delete cascade,
  parada_omsa_id uuid not null references public.paradas_omsa(id) on delete cascade,
  secuencia integer not null,
  tiempo_desde_inicio_min numeric(8,2),
  distancia_acumulada_m integer,
  created_at timestamptz not null default now(),
  unique (ruta_omsa_id, secuencia)
);

-- -------------------------
-- 3.4 Categorías y Lugares
-- -------------------------
create table if not exists public.categorias_lugares (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  nombre text not null,
  nombre_norm text generated always as (public.normalize_text(nombre)) stored,
  descripcion text,
  created_at timestamptz not null default now()
);

create table if not exists public.lugares (
  id uuid primary key default gen_random_uuid(),
  categoria_id uuid references public.categorias_lugares(id) on delete set null,
  codigo_externo text unique,
  nombre text not null,
  nombre_norm text generated always as (public.normalize_text(nombre)) stored,
  descripcion text,
  direccion text,
  sector text,
  municipio text default 'Santo Domingo',
  lat double precision not null,
  lon double precision not null,
  popularidad integer not null default 50 check (popularidad between 0 and 100),
  activo boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.lugares_aliases (
  id uuid primary key default gen_random_uuid(),
  lugar_id uuid not null references public.lugares(id) on delete cascade,
  alias text not null,
  alias_norm text generated always as (public.normalize_text(alias)) stored,
  es_principal boolean not null default false,
  created_at timestamptz not null default now(),
  unique (lugar_id, alias_norm)
);

-- -------------------------
-- 3.5 Diccionario local / dominicanismos
-- -------------------------
create table if not exists public.diccionario_local (
  id uuid primary key default gen_random_uuid(),
  termino text not null,
  termino_norm text generated always as (public.normalize_text(termino)) stored,
  canonico text not null,
  canonico_norm text generated always as (public.normalize_text(canonico)) stored,
  tipo_entidad text not null check (
    tipo_entidad in ('estacion', 'parada_omsa', 'lugar', 'linea', 'ruta_omsa', 'general')
  ),
  entidad_id uuid,
  prioridad integer not null default 100,
  notas text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- -------------------------
-- 3.6 Nodos genéricos para el motor de rutas
-- -------------------------
create table if not exists public.nodos (
  id uuid primary key default gen_random_uuid(),
  tipo_fuente text not null check (tipo_fuente in ('estacion', 'parada_omsa', 'lugar')),
  fuente_id uuid not null,
  codigo text not null unique,
  nombre text not null,
  nombre_norm text generated always as (public.normalize_text(nombre)) stored,
  lat double precision not null,
  lon double precision not null,
  linea_id uuid references public.lineas(id) on delete set null,
  activo boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tipo_fuente, fuente_id)
);

-- -------------------------
-- 3.7 Accesos desde lugares a transporte
-- Un lugar puede tener varias estaciones/paradas cercanas.
-- -------------------------
create table if not exists public.lugar_accesos (
  id uuid primary key default gen_random_uuid(),
  lugar_id uuid not null references public.lugares(id) on delete cascade,
  estacion_id uuid references public.estaciones(id) on delete cascade,
  parada_omsa_id uuid references public.paradas_omsa(id) on delete cascade,
  distancia_m integer not null check (distancia_m >= 0),
  tiempo_caminando_min numeric(8,2) not null check (tiempo_caminando_min >= 0),
  prioridad integer not null default 1,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  check (num_nonnulls(estacion_id, parada_omsa_id) = 1)
);

-- -------------------------
-- 3.8 Aristas del grafo
-- Aquí irá el corazón del motor de rutas.
-- -------------------------
create table if not exists public.aristas (
  id uuid primary key default gen_random_uuid(),
  origen_nodo_id uuid not null references public.nodos(id) on delete cascade,
  destino_nodo_id uuid not null references public.nodos(id) on delete cascade,
  tipo text not null check (tipo in ('metro', 'teleferico', 'omsa', 'caminata', 'transbordo')),
  linea_id uuid references public.lineas(id) on delete set null,
  ruta_omsa_id uuid references public.rutas_omsa(id) on delete set null,
  descripcion text,
  tiempo_min numeric(8,2) not null check (tiempo_min >= 0),
  distancia_m integer not null default 0 check (distancia_m >= 0),
  penalizacion numeric(8,2) not null default 0 check (penalizacion >= 0),
  bidireccional boolean not null default false,
  activo boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (origen_nodo_id <> destino_nodo_id)
);

-- -------------------------
-- 3.9 Avisos y estado de servicio
-- -------------------------
create table if not exists public.avisos_servicio (
  id uuid primary key default gen_random_uuid(),
  modo text not null check (modo in ('metro', 'teleferico', 'omsa', 'general')),
  linea_id uuid references public.lineas(id) on delete set null,
  ruta_omsa_id uuid references public.rutas_omsa(id) on delete set null,
  severidad text not null check (severidad in ('info', 'warning', 'critical')),
  titulo text not null,
  mensaje text not null,
  fecha_inicio timestamptz not null default now(),
  fecha_fin timestamptz,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- -------------------------
-- 3.10 Logs de consultas del chatbot
-- -------------------------
create table if not exists public.consultas_chat (
  id uuid primary key default gen_random_uuid(),
  session_id text,
  user_id uuid,
  tipo_input text not null check (tipo_input in ('texto', 'audio')),
  texto_original text,
  texto_normalizado text generated always as (public.normalize_text(texto_original)) stored,
  origen_detectado text,
  destino_detectado text,
  origen_nodo_id uuid references public.nodos(id) on delete set null,
  destino_nodo_id uuid references public.nodos(id) on delete set null,
  intencion text,
  respuesta_generada text,
  confidence numeric(5,4) check (confidence >= 0 and confidence <= 1),
  duracion_ms integer,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- -------------------------
-- 3.11 Casos de prueba y resultados
-- -------------------------
create table if not exists public.casos_prueba (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  input_text text not null,
  input_norm text generated always as (public.normalize_text(input_text)) stored,
  expected_origin_text text,
  expected_destination_text text,
  expected_max_eta_min numeric(8,2),
  expected_max_transbordos integer,
  activo boolean not null default true,
  notas text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.resultados_prueba (
  id uuid primary key default gen_random_uuid(),
  caso_prueba_id uuid not null references public.casos_prueba(id) on delete cascade,
  version_bot text,
  passed boolean not null,
  actual_origin_text text,
  actual_destination_text text,
  actual_eta_min numeric(8,2),
  actual_transbordos integer,
  respuesta_resumen text,
  detalles jsonb not null default '{}'::jsonb,
  executed_at timestamptz not null default now()
);

-- =========================================================
-- 4) ÍNDICES
-- =========================================================

create index if not exists idx_lineas_nombre_norm_trgm
  on public.lineas using gin (nombre_norm gin_trgm_ops);

create index if not exists idx_estaciones_linea_id
  on public.estaciones (linea_id);

create index if not exists idx_estaciones_nombre_norm_trgm
  on public.estaciones using gin (nombre_norm gin_trgm_ops);

create index if not exists idx_estaciones_lat_lon
  on public.estaciones (lat, lon);

create index if not exists idx_estaciones_aliases_estacion_id
  on public.estaciones_aliases (estacion_id);

create index if not exists idx_estaciones_aliases_alias_norm_trgm
  on public.estaciones_aliases using gin (alias_norm gin_trgm_ops);

create index if not exists idx_rutas_omsa_nombre_norm_trgm
  on public.rutas_omsa using gin (nombre_norm gin_trgm_ops);

create index if not exists idx_rutas_omsa_linea_id
  on public.rutas_omsa (linea_id);

create index if not exists idx_paradas_omsa_nombre_norm_trgm
  on public.paradas_omsa using gin (nombre_norm gin_trgm_ops);

create index if not exists idx_paradas_omsa_lat_lon
  on public.paradas_omsa (lat, lon);

create index if not exists idx_paradas_omsa_aliases_parada_id
  on public.paradas_omsa_aliases (parada_omsa_id);

create index if not exists idx_paradas_omsa_aliases_alias_norm_trgm
  on public.paradas_omsa_aliases using gin (alias_norm gin_trgm_ops);

create index if not exists idx_rutas_omsa_paradas_ruta_secuencia
  on public.rutas_omsa_paradas (ruta_omsa_id, secuencia);

create index if not exists idx_rutas_omsa_paradas_parada_id
  on public.rutas_omsa_paradas (parada_omsa_id);

create index if not exists idx_categorias_lugares_nombre_norm_trgm
  on public.categorias_lugares using gin (nombre_norm gin_trgm_ops);

create index if not exists idx_lugares_categoria_id
  on public.lugares (categoria_id);

create index if not exists idx_lugares_nombre_norm_trgm
  on public.lugares using gin (nombre_norm gin_trgm_ops);

create index if not exists idx_lugares_lat_lon
  on public.lugares (lat, lon);

create index if not exists idx_lugares_aliases_lugar_id
  on public.lugares_aliases (lugar_id);

create index if not exists idx_lugares_aliases_alias_norm_trgm
  on public.lugares_aliases using gin (alias_norm gin_trgm_ops);

create index if not exists idx_diccionario_local_termino_norm_trgm
  on public.diccionario_local using gin (termino_norm gin_trgm_ops);

create index if not exists idx_diccionario_local_canonico_norm_trgm
  on public.diccionario_local using gin (canonico_norm gin_trgm_ops);

create index if not exists idx_nodos_tipo_fuente_fuente_id
  on public.nodos (tipo_fuente, fuente_id);

create index if not exists idx_nodos_nombre_norm_trgm
  on public.nodos using gin (nombre_norm gin_trgm_ops);

create index if not exists idx_nodos_lat_lon
  on public.nodos (lat, lon);

create index if not exists idx_lugar_accesos_lugar_id
  on public.lugar_accesos (lugar_id);

create index if not exists idx_lugar_accesos_estacion_id
  on public.lugar_accesos (estacion_id);

create index if not exists idx_lugar_accesos_parada_id
  on public.lugar_accesos (parada_omsa_id);

create unique index if not exists uq_lugar_accesos_lugar_estacion
  on public.lugar_accesos (lugar_id, estacion_id)
  where estacion_id is not null;

create unique index if not exists uq_lugar_accesos_lugar_parada
  on public.lugar_accesos (lugar_id, parada_omsa_id)
  where parada_omsa_id is not null;

create index if not exists idx_aristas_origen
  on public.aristas (origen_nodo_id);

create index if not exists idx_aristas_destino
  on public.aristas (destino_nodo_id);

create index if not exists idx_aristas_tipo
  on public.aristas (tipo);

create index if not exists idx_aristas_linea_id
  on public.aristas (linea_id);

create index if not exists idx_aristas_ruta_omsa_id
  on public.aristas (ruta_omsa_id);

create index if not exists idx_avisos_servicio_activo
  on public.avisos_servicio (activo, fecha_inicio, fecha_fin);

create index if not exists idx_consultas_chat_session_id
  on public.consultas_chat (session_id);

create index if not exists idx_consultas_chat_created_at
  on public.consultas_chat (created_at desc);

create index if not exists idx_casos_prueba_input_norm_trgm
  on public.casos_prueba using gin (input_norm gin_trgm_ops);

create index if not exists idx_resultados_prueba_caso_id
  on public.resultados_prueba (caso_prueba_id);

-- =========================================================
-- 5) TRIGGERS updated_at
-- =========================================================

drop trigger if exists trg_touch_lineas on public.lineas;
create trigger trg_touch_lineas
before update on public.lineas
for each row execute function public.touch_updated_at();

drop trigger if exists trg_touch_estaciones on public.estaciones;
create trigger trg_touch_estaciones
before update on public.estaciones
for each row execute function public.touch_updated_at();

drop trigger if exists trg_touch_rutas_omsa on public.rutas_omsa;
create trigger trg_touch_rutas_omsa
before update on public.rutas_omsa
for each row execute function public.touch_updated_at();

drop trigger if exists trg_touch_paradas_omsa on public.paradas_omsa;
create trigger trg_touch_paradas_omsa
before update on public.paradas_omsa
for each row execute function public.touch_updated_at();

drop trigger if exists trg_touch_lugares on public.lugares;
create trigger trg_touch_lugares
before update on public.lugares
for each row execute function public.touch_updated_at();

drop trigger if exists trg_touch_diccionario_local on public.diccionario_local;
create trigger trg_touch_diccionario_local
before update on public.diccionario_local
for each row execute function public.touch_updated_at();

drop trigger if exists trg_touch_nodos on public.nodos;
create trigger trg_touch_nodos
before update on public.nodos
for each row execute function public.touch_updated_at();

drop trigger if exists trg_touch_aristas on public.aristas;
create trigger trg_touch_aristas
before update on public.aristas
for each row execute function public.touch_updated_at();

drop trigger if exists trg_touch_avisos_servicio on public.avisos_servicio;
create trigger trg_touch_avisos_servicio
before update on public.avisos_servicio
for each row execute function public.touch_updated_at();

drop trigger if exists trg_touch_casos_prueba on public.casos_prueba;
create trigger trg_touch_casos_prueba
before update on public.casos_prueba
for each row execute function public.touch_updated_at();

-- =========================================================
-- 6) VISTA UNIFICADA DE BÚSQUEDA
-- =========================================================

create or replace view public.v_catalogo_busqueda as
select
  'linea'::text as tipo_entidad,
  l.id as entidad_id,
  l.nombre as nombre_mostrar,
  l.nombre_norm as texto_busqueda,
  null::double precision as lat,
  null::double precision as lon,
  'nombre'::text as fuente
from public.lineas l

union all

select
  'estacion'::text,
  e.id,
  e.nombre,
  e.nombre_norm,
  e.lat,
  e.lon,
  'nombre'::text
from public.estaciones e

union all

select
  'estacion'::text,
  ea.estacion_id,
  e.nombre,
  ea.alias_norm,
  e.lat,
  e.lon,
  'alias'::text
from public.estaciones_aliases ea
join public.estaciones e on e.id = ea.estacion_id

union all

select
  'ruta_omsa'::text,
  r.id,
  r.nombre,
  r.nombre_norm,
  null::double precision,
  null::double precision,
  'nombre'::text
from public.rutas_omsa r

union all

select
  'parada_omsa'::text,
  p.id,
  p.nombre,
  p.nombre_norm,
  p.lat,
  p.lon,
  'nombre'::text
from public.paradas_omsa p

union all

select
  'parada_omsa'::text,
  pa.parada_omsa_id,
  p.nombre,
  pa.alias_norm,
  p.lat,
  p.lon,
  'alias'::text
from public.paradas_omsa_aliases pa
join public.paradas_omsa p on p.id = pa.parada_omsa_id

union all

select
  'lugar'::text,
  l.id,
  l.nombre,
  l.nombre_norm,
  l.lat,
  l.lon,
  'nombre'::text
from public.lugares l

union all

select
  'lugar'::text,
  la.lugar_id,
  l.nombre,
  la.alias_norm,
  l.lat,
  l.lon,
  'alias'::text
from public.lugares_aliases la
join public.lugares l on l.id = la.lugar_id;

-- =========================================================
-- 7) FUNCIÓN RPC DE BÚSQUEDA DIFUSA
-- =========================================================

create or replace function public.search_catalog(
  q text,
  limit_rows integer default 10
)
returns table (
  tipo_entidad text,
  entidad_id uuid,
  nombre_mostrar text,
  texto_busqueda text,
  fuente text,
  lat double precision,
  lon double precision,
  score real
)
language sql
stable
as $$
  with params as (
    select public.normalize_text(q) as qn
  )
  select
    c.tipo_entidad,
    c.entidad_id,
    c.nombre_mostrar,
    c.texto_busqueda,
    c.fuente,
    c.lat,
    c.lon,
    greatest(
      similarity(c.texto_busqueda, p.qn),
      similarity(public.normalize_text(c.nombre_mostrar), p.qn)
    )::real as score
  from public.v_catalogo_busqueda c
  cross join params p
  where
    c.texto_busqueda % p.qn
    or c.texto_busqueda like '%' || p.qn || '%'
    or p.qn like '%' || c.texto_busqueda || '%'
  order by score desc, c.nombre_mostrar asc
  limit greatest(limit_rows, 1);
$$;

-- =========================================================
-- 8) FUNCIONES PARA SINCRONIZAR NODOS
-- Después de cargar estaciones, paradas y lugares,
-- ejecuta: select public.sync_all_nodos();
-- =========================================================

create or replace function public.sync_nodos_estaciones()
returns integer
language plpgsql
as $$
declare
  v_count integer;
begin
  insert into public.nodos (
    tipo_fuente,
    fuente_id,
    codigo,
    nombre,
    lat,
    lon,
    linea_id,
    activo,
    metadata
  )
  select
    'estacion',
    e.id,
    e.codigo,
    e.nombre,
    e.lat,
    e.lon,
    e.linea_id,
    e.activa,
    jsonb_build_object('tabla', 'estaciones')
  from public.estaciones e
  on conflict (tipo_fuente, fuente_id)
  do update set
    codigo = excluded.codigo,
    nombre = excluded.nombre,
    lat = excluded.lat,
    lon = excluded.lon,
    linea_id = excluded.linea_id,
    activo = excluded.activo,
    metadata = excluded.metadata,
    updated_at = now();

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.sync_nodos_paradas_omsa()
returns integer
language plpgsql
as $$
declare
  v_count integer;
begin
  insert into public.nodos (
    tipo_fuente,
    fuente_id,
    codigo,
    nombre,
    lat,
    lon,
    linea_id,
    activo,
    metadata
  )
  select
    'parada_omsa',
    p.id,
    coalesce(p.codigo, 'parada-' || replace(p.id::text, '-', '')),
    p.nombre,
    p.lat,
    p.lon,
    null,
    p.activa,
    jsonb_build_object('tabla', 'paradas_omsa')
  from public.paradas_omsa p
  on conflict (tipo_fuente, fuente_id)
  do update set
    codigo = excluded.codigo,
    nombre = excluded.nombre,
    lat = excluded.lat,
    lon = excluded.lon,
    linea_id = excluded.linea_id,
    activo = excluded.activo,
    metadata = excluded.metadata,
    updated_at = now();

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.sync_nodos_lugares()
returns integer
language plpgsql
as $$
declare
  v_count integer;
begin
  insert into public.nodos (
    tipo_fuente,
    fuente_id,
    codigo,
    nombre,
    lat,
    lon,
    linea_id,
    activo,
    metadata
  )
  select
    'lugar',
    l.id,
    coalesce(l.codigo_externo, 'lugar-' || replace(l.id::text, '-', '')),
    l.nombre,
    l.lat,
    l.lon,
    null,
    l.activo,
    jsonb_build_object('tabla', 'lugares')
  from public.lugares l
  on conflict (tipo_fuente, fuente_id)
  do update set
    codigo = excluded.codigo,
    nombre = excluded.nombre,
    lat = excluded.lat,
    lon = excluded.lon,
    linea_id = excluded.linea_id,
    activo = excluded.activo,
    metadata = excluded.metadata,
    updated_at = now();

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.sync_all_nodos()
returns jsonb
language plpgsql
as $$
declare
  v_estaciones integer;
  v_paradas integer;
  v_lugares integer;
begin
  v_estaciones := public.sync_nodos_estaciones();
  v_paradas := public.sync_nodos_paradas_omsa();
  v_lugares := public.sync_nodos_lugares();

  return jsonb_build_object(
    'estaciones', v_estaciones,
    'paradas_omsa', v_paradas,
    'lugares', v_lugares
  );
end;
$$;

-- =========================================================
-- 9) DATOS SEMILLA DE CATEGORÍAS
-- =========================================================

insert into public.categorias_lugares (slug, nombre, descripcion)
values
  ('estacion-metro', 'Estación Metro', 'Puntos del Metro'),
  ('estacion-teleferico', 'Estación Teleférico', 'Puntos del Teleférico'),
  ('parada-omsa', 'Parada OMSA', 'Paradas de la OMSA'),
  ('universidad', 'Universidad', 'Centros universitarios'),
  ('escuela', 'Escuela', 'Centros educativos'),
  ('hospital', 'Hospital', 'Hospitales y centros médicos'),
  ('clinica', 'Clínica', 'Clínicas privadas'),
  ('farmacia', 'Farmacia', 'Farmacias'),
  ('supermercado', 'Supermercado', 'Supermercados'),
  ('plaza', 'Plaza Comercial', 'Plazas y malls'),
  ('banco', 'Banco', 'Sucursales bancarias'),
  ('gobierno', 'Oficina Gubernamental', 'Instituciones públicas'),
  ('parque', 'Parque', 'Parques y áreas verdes'),
  ('iglesia', 'Iglesia', 'Templos e iglesias'),
  ('barrio', 'Barrio', 'Barrios y sectores'),
  ('avenida', 'Avenida', 'Avenidas importantes'),
  ('calle', 'Calle', 'Calles relevantes'),
  ('restaurante', 'Restaurante', 'Restaurantes'),
  ('turistico', 'Lugar Turístico', 'Puntos turísticos'),
  ('deporte', 'Centro Deportivo', 'Canchas y centros deportivos'),
  ('terminal', 'Terminal', 'Terminales de transporte'),
  ('edificio', 'Edificio', 'Edificios conocidos')
on conflict (slug) do nothing;

-- =========================================================
-- 10) RLS Y POLÍTICAS
-- Referencia pública de solo lectura para la app.
-- Logs y pruebas quedan privadas.
-- =========================================================

alter table public.lineas enable row level security;
alter table public.estaciones enable row level security;
alter table public.estaciones_aliases enable row level security;
alter table public.rutas_omsa enable row level security;
alter table public.paradas_omsa enable row level security;
alter table public.paradas_omsa_aliases enable row level security;
alter table public.rutas_omsa_paradas enable row level security;
alter table public.categorias_lugares enable row level security;
alter table public.lugares enable row level security;
alter table public.lugares_aliases enable row level security;
alter table public.diccionario_local enable row level security;
alter table public.nodos enable row level security;
alter table public.lugar_accesos enable row level security;
alter table public.aristas enable row level security;
alter table public.avisos_servicio enable row level security;

alter table public.consultas_chat enable row level security;
alter table public.casos_prueba enable row level security;
alter table public.resultados_prueba enable row level security;

drop policy if exists "read_lineas" on public.lineas;
create policy "read_lineas" on public.lineas
for select to anon, authenticated
using (true);

drop policy if exists "read_estaciones" on public.estaciones;
create policy "read_estaciones" on public.estaciones
for select to anon, authenticated
using (true);

drop policy if exists "read_estaciones_aliases" on public.estaciones_aliases;
create policy "read_estaciones_aliases" on public.estaciones_aliases
for select to anon, authenticated
using (true);

drop policy if exists "read_rutas_omsa" on public.rutas_omsa;
create policy "read_rutas_omsa" on public.rutas_omsa
for select to anon, authenticated
using (true);

drop policy if exists "read_paradas_omsa" on public.paradas_omsa;
create policy "read_paradas_omsa" on public.paradas_omsa
for select to anon, authenticated
using (true);

drop policy if exists "read_paradas_omsa_aliases" on public.paradas_omsa_aliases;
create policy "read_paradas_omsa_aliases" on public.paradas_omsa_aliases
for select to anon, authenticated
using (true);

drop policy if exists "read_rutas_omsa_paradas" on public.rutas_omsa_paradas;
create policy "read_rutas_omsa_paradas" on public.rutas_omsa_paradas
for select to anon, authenticated
using (true);

drop policy if exists "read_categorias_lugares" on public.categorias_lugares;
create policy "read_categorias_lugares" on public.categorias_lugares
for select to anon, authenticated
using (true);

drop policy if exists "read_lugares" on public.lugares;
create policy "read_lugares" on public.lugares
for select to anon, authenticated
using (true);

drop policy if exists "read_lugares_aliases" on public.lugares_aliases;
create policy "read_lugares_aliases" on public.lugares_aliases
for select to anon, authenticated
using (true);

drop policy if exists "read_diccionario_local" on public.diccionario_local;
create policy "read_diccionario_local" on public.diccionario_local
for select to anon, authenticated
using (true);

drop policy if exists "read_nodos" on public.nodos;
create policy "read_nodos" on public.nodos
for select to anon, authenticated
using (true);

drop policy if exists "read_lugar_accesos" on public.lugar_accesos;
create policy "read_lugar_accesos" on public.lugar_accesos
for select to anon, authenticated
using (true);

drop policy if exists "read_aristas" on public.aristas;
create policy "read_aristas" on public.aristas
for select to anon, authenticated
using (true);

drop policy if exists "read_avisos_servicio" on public.avisos_servicio;
create policy "read_avisos_servicio" on public.avisos_servicio
for select to anon, authenticated
using (true);

grant usage on schema public to anon, authenticated;
grant select on public.lineas to anon, authenticated;
grant select on public.estaciones to anon, authenticated;
grant select on public.estaciones_aliases to anon, authenticated;
grant select on public.rutas_omsa to anon, authenticated;
grant select on public.paradas_omsa to anon, authenticated;
grant select on public.paradas_omsa_aliases to anon, authenticated;
grant select on public.rutas_omsa_paradas to anon, authenticated;
grant select on public.categorias_lugares to anon, authenticated;
grant select on public.lugares to anon, authenticated;
grant select on public.lugares_aliases to anon, authenticated;
grant select on public.diccionario_local to anon, authenticated;
grant select on public.nodos to anon, authenticated;
grant select on public.lugar_accesos to anon, authenticated;
grant select on public.aristas to anon, authenticated;
grant select on public.avisos_servicio to anon, authenticated;
grant select on public.v_catalogo_busqueda to anon, authenticated;

grant execute on function public.search_catalog(text, integer) to anon, authenticated;
grant execute on function public.haversine_m(double precision, double precision, double precision, double precision) to anon, authenticated;

commit;

alter table public.lineas
add column if not exists estado_operacion text not null default 'normal'
check (estado_operacion in ('normal', 'marcha_blanca', 'mantenimiento', 'suspendida', 'planificada'));

insert into public.lineas (codigo, nombre, modo, color_hex, descripcion, orden_visual, activa, estado_operacion)
values
  ('L1',  'Línea 1', 'metro',       '#00A651', 'Metro de Santo Domingo - Línea 1', 1, true,  'normal'),
  ('L2',  'Línea 2', 'metro',       '#ED1C24', 'Metro de Santo Domingo - Línea 2', 2, true,  'normal'),
  ('L2C', 'Línea 2C', 'metro',      '#F97316', 'Extensión de la Línea 2 hacia Los Alcarrizos', 3, true, 'marcha_blanca'),
  ('T1',  'Línea 1', 'teleferico',  '#3B82F6', 'Teleférico de Santo Domingo - Línea 1', 4, true, 'normal')
on conflict (codigo) do update
set
  nombre = excluded.nombre,
  modo = excluded.modo,
  color_hex = excluded.color_hex,
  descripcion = excluded.descripcion,
  orden_visual = excluded.orden_visual,
  activa = excluded.activa,
  estado_operacion = excluded.estado_operacion,
  updated_at = now();