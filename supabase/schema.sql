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

-- Visitas: el público puede INSERTAR (registrar su visita).
-- La LECTURA queda restringida a usuarios autenticados
-- (el panel de coordinadores exige sesión).
drop policy if exists "visitas_public_insert" on public.visitas;
create policy "visitas_public_insert"
  on public.visitas for insert
  with check (true);

drop policy if exists "visitas_authenticated_read" on public.visitas;
create policy "visitas_authenticated_read"
  on public.visitas for select
  to authenticated
  using (auth.role() = 'authenticated');

-- ============================================================
-- Tabla de configuración (aquí vive el PIN de coordinadores)
-- RLS activo y SIN policies: nadie puede leerla ni escribirla
-- directamente. Solo se accede vía la función validar_pin().
-- ============================================================
create extension if not exists pgcrypto;

create table if not exists public.app_config (
  llave text primary key,
  valor text not null
);

alter table public.app_config enable row level security;

-- ============================================================
-- Registrar una visita (seguridad definer)
-- El panel alumno la invoca vía RPC en vez de insert().select():
-- con el SELECT de visitas restringido, la cláusula RETURNING del
-- INSERT fallaría para usuarios anónimos. Esta función corre como
-- owner (bypassa RLS) y devuelve el id y fecha para el folio.
-- ============================================================
create or replace function public.registrar_visita(
  p_alumno_id text,
  p_sigla text,
  p_motivo text
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id bigint;
  v_registrada_en timestamptz;
begin
  insert into public.visitas (alumno_id, sigla, motivo)
  values (p_alumno_id, p_sigla, p_motivo)
  returning id, registrada_en into v_id, v_registrada_en;

  return json_build_object(
    'id', v_id,
    'registrada_en', v_registrada_en
  );
end;
$$;

revoke all on function public.registrar_visita(text, text, text) from public;
grant execute on function public.registrar_visita(text, text, text) to anon;

-- ============================================================
-- Validar PIN de coordinadores (seguridad definer)
-- Compara con crypt() (pgcrypto) contra la tabla app_config.
-- El PIN en sí nunca se expone; solo se responde true/false.
-- Insertar el PIN (hash) manualmente desde el SQL Editor:
--   insert into public.app_config (llave, valor)
--   values ('coordinador_pin', crypt('TU_PIN', gen_salt('bf')));
-- ============================================================
create or replace function public.validar_pin(p_pin text)
returns boolean
language sql
security definer
set search_path = public, extensions
as $$
  select exists(
    select 1
    from public.app_config
    where llave = 'coordinador_pin'
      and valor = crypt(p_pin, valor)
  );
$$;

revoke all on function public.validar_pin(text) from public;
grant execute on function public.validar_pin(text) to anon, authenticated;
