begin;

create table if not exists public.import_estaciones_raw (
  id bigserial primary key,
  linea_codigo text not null,
  estacion_codigo text,
  nombre text not null,
  orden_en_linea integer not null,
  es_terminal boolean default false,
  es_transbordo boolean default false,
  lat double precision,
  lon double precision,
  municipio text,
  sector text,
  direccion_referencia text,
  fuente text,
  fuente_url text,
  observaciones text,
  created_at timestamptz not null default now()
);

create table if not exists public.import_paradas_omsa_raw (
  id bigserial primary key,
  ruta_codigo text,
  parada_codigo text,
  nombre text not null,
  secuencia integer,
  lat double precision,
  lon double precision,
  municipio text,
  sector text,
  direccion_referencia text,
  fuente text,
  fuente_url text,
  observaciones text,
  created_at timestamptz not null default now()
);

create table if not exists public.import_lugares_raw (
  id bigserial primary key,
  categoria_slug text,
  nombre text not null,
  direccion text,
  sector text,
  municipio text default 'Santo Domingo',
  lat double precision,
  lon double precision,
  fuente text,
  fuente_url text,
  observaciones text,
  created_at timestamptz not null default now()
);

commit;