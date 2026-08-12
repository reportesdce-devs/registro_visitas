-- ============================================================
-- Supabase · registro_visitas
-- Validado contra "REGISTRO DE VISTAS.xlsx" (hojas: Alumnos, Visitas)
-- Ejecutar en: SQL Editor -> New query -> Run
-- ============================================================

-- ============================================================
-- Hoja "Alumnos": ID, Nombre, Carrera
-- (la hoja NO tiene columna Sigla; la carrera es el nombre completo)
-- ============================================================
create table if not exists public.alumnos (
  id text primary key,
  nombre text not null,
  carrera text not null
);

-- Carreras existentes:
--   Ingeniería Industrial           -> sigla II
--   Ingeniería Mecatrónica          -> sigla IM
--   Ingeniería Química              -> sigla IQ
--   Sistemas y Negocios Digitales   -> sigla ISND

-- ============================================================
-- Hoja "Visitas": Timestamp, Folio, Fecha ISO, Fecha, Hora,
--                 ID, Nombre, Carrera, Sigla, Motivo
--   * folio -> id (bigserial); el formato AT-YYYY-NNNNN se
--     genera en el frontend: AT-2026-00001
--   * Timestamp/Fecha ISO/Fecha/Hora -> registrada_en (UTC)
--   * Nombre y Carrera (full name) -> se obtienen con JOIN
--     a public.alumnos
-- ============================================================
create table if not exists public.visitas (
  id bigserial primary key,
  alumno_id text not null references public.alumnos(id) on delete restrict,
  sigla text not null check (sigla in ('IQ','ISND','IM','II')),
  motivo text not null,
  registrada_en timestamptz not null default now()
);

-- Índices para consultas rápidas
create index if not exists visitas_alumno_idx on public.visitas (alumno_id);
create index if not exists visitas_fecha_idx on public.visitas (registrada_en desc);

-- ============================================================
-- Row Level Security (RLS)
-- ============================================================
alter table public.alumnos enable row level security;
alter table public.visitas enable row level security;

-- Alumnos: lectura pública (necesaria para resolver nombre/carrera
-- a partir del ID capturado en el formulario)
drop policy if exists "alumnos_public_read" on public.alumnos;
create policy "alumnos_public_read"
  on public.alumnos for select
  using (true);

-- Visitas: el público puede INSERTAR (registrar su visita)
-- y LEER (el panel de coordinadores lo necesita; mismo acceso
-- abierto que tenía con Google Sheets).
-- Para protegerlo con auth en el futuro, cambia la policy de
-- select a: using (auth.role() = 'authenticated');
drop policy if exists "visitas_public_insert" on public.visitas;
create policy "visitas_public_insert"
  on public.visitas for insert
  with check (true);

drop policy if exists "visitas_public_read" on public.visitas;
create policy "visitas_public_read"
  on public.visitas for select
  using (true);
