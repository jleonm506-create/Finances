-- ============================================================
--  Presupuesto por sobres — esquema Supabase
--  Modelo: hogar compartido, ciclo quincenal, asignación-primero
-- ============================================================

create extension if not exists "pgcrypto";

-- ------------------------------------------------------------
--  HOGAR  — dos personas, una bolsa común
-- ------------------------------------------------------------
create table hogares (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null,
  moneda_base text not null default 'CRC' check (moneda_base in ('CRC','USD')),
  creado_en   timestamptz not null default now()
);

create table miembros (
  hogar_id    uuid not null references hogares(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  nombre      text not null,
  rol         text not null default 'socio' check (rol in ('socio','invitado')),
  creado_en   timestamptz not null default now(),
  primary key (hogar_id, user_id)
);

-- Helper SECURITY DEFINER: evita recursión de RLS al consultar miembros
create or replace function hogar_actual()
returns uuid
language sql stable security definer set search_path = public
as $$ select hogar_id from miembros where user_id = auth.uid() limit 1 $$;

-- ------------------------------------------------------------
--  PERIODOS  — la quincena es la unidad de todo
-- ------------------------------------------------------------
create table periodos (
  id            uuid primary key default gen_random_uuid(),
  hogar_id      uuid not null references hogares(id) on delete cascade,
  inicio        date not null,
  fin           date not null,
  estado        text not null default 'planificando'
                check (estado in ('planificando','activo','cerrado')),
  cerrado_en    timestamptz,
  creado_en     timestamptz not null default now(),
  unique (hogar_id, inicio),
  check (fin > inicio)
);
create index on periodos (hogar_id, inicio desc);

-- Ingresos reales que entraron en el periodo (él + ella + extras)
create table ingresos (
  id          uuid primary key default gen_random_uuid(),
  hogar_id    uuid not null references hogares(id) on delete cascade,
  periodo_id  uuid not null references periodos(id) on delete cascade,
  miembro_id  uuid references auth.users(id) on delete set null,
  concepto    text not null,
  monto       numeric(14,2) not null check (monto > 0),
  moneda      text not null default 'CRC' check (moneda in ('CRC','USD')),
  fecha       date not null default current_date,
  creado_en   timestamptz not null default now()
);
create index on ingresos (periodo_id);

-- ------------------------------------------------------------
--  SOBRES  — clasificados por PREDICTIBILIDAD, no por tema.
--  Esto es lo que decide cuánto tenés que acordarte de registrar.
--    fijo     → monto conocido, se marca pagado. Cero registro.
--    deuda    → amortiza solo. Cero registro.
--    variable → único que exige registro manual.
--    ahorro   → acumula hacia una meta.
-- ------------------------------------------------------------
create table sobres (
  id            uuid primary key default gen_random_uuid(),
  hogar_id      uuid not null references hogares(id) on delete cascade,
  nombre        text not null,
  tipo          text not null check (tipo in ('fijo','deuda','variable','ahorro')),
  color         text not null default '#5C6470',
  icono         text,
  -- fijo: monto esperado por periodo y día de corte
  monto_esperado numeric(14,2),
  dia_corte      smallint check (dia_corte between 1 and 31),
  -- ahorro: meta y fecha objetivo
  meta           numeric(14,2),
  meta_fecha     date,
  -- acumula saldo no gastado al siguiente periodo (típico en ahorro y fijo)
  acumula        boolean not null default false,
  orden          smallint not null default 0,
  activo         boolean not null default true,
  creado_en      timestamptz not null default now()
);
create index on sobres (hogar_id, activo, orden);

-- ------------------------------------------------------------
--  DEUDAS  — detalle financiero de los sobres tipo 'deuda'
-- ------------------------------------------------------------
create table deudas (
  sobre_id        uuid primary key references sobres(id) on delete cascade,
  acreedor        text not null,
  saldo_inicial   numeric(14,2) not null check (saldo_inicial > 0),
  saldo_actual    numeric(14,2) not null,
  tasa_anual      numeric(6,3) not null default 0,   -- % nominal anual
  cuota_minima    numeric(14,2) not null default 0,
  moneda          text not null default 'CRC' check (moneda in ('CRC','USD')),
  fecha_corte     smallint check (fecha_corte between 1 and 31),
  prioridad       smallint not null default 0        -- orden de ataque manual
);

create table pagos_deuda (
  id          uuid primary key default gen_random_uuid(),
  sobre_id    uuid not null references sobres(id) on delete cascade,
  periodo_id  uuid references periodos(id) on delete set null,
  monto       numeric(14,2) not null check (monto > 0),
  interes     numeric(14,2) not null default 0,
  capital     numeric(14,2) generated always as (monto - interes) stored,
  fecha       date not null default current_date,
  nota        text,
  creado_en   timestamptz not null default now()
);
create index on pagos_deuda (sobre_id, fecha desc);

-- ------------------------------------------------------------
--  ASIGNACIONES  — el acto de repartir la quincena.
--  Este es el registro que SÍ se hace siempre. Fuente de verdad.
-- ------------------------------------------------------------
create table asignaciones (
  id          uuid primary key default gen_random_uuid(),
  periodo_id  uuid not null references periodos(id) on delete cascade,
  sobre_id    uuid not null references sobres(id) on delete cascade,
  monto       numeric(14,2) not null check (monto >= 0),
  pagado      boolean not null default false,   -- para sobres fijos y deuda
  pagado_en   timestamptz,
  creado_en   timestamptz not null default now(),
  unique (periodo_id, sobre_id)
);
create index on asignaciones (periodo_id);

-- ------------------------------------------------------------
--  MOVIMIENTOS  — registro granular. Opcional por diseño.
--  Solo importa de verdad en sobres tipo 'variable'.
-- ------------------------------------------------------------
create table movimientos (
  id            uuid primary key default gen_random_uuid(),
  hogar_id      uuid not null references hogares(id) on delete cascade,
  periodo_id    uuid references periodos(id) on delete set null,
  sobre_id      uuid references sobres(id) on delete set null,
  monto         numeric(14,2) not null check (monto > 0),
  moneda        text not null default 'CRC' check (moneda in ('CRC','USD')),
  comercio      text,
  nota          text,
  fecha         timestamptz not null default now(),
  registrado_por uuid references auth.users(id) on delete set null,
  creado_en     timestamptz not null default now()
);
create index on movimientos (hogar_id, fecha desc);
create index on movimientos (periodo_id, sobre_id);

-- Reglas de autocategorización: cada corrección manual enseña al sistema
create table reglas (
  id          uuid primary key default gen_random_uuid(),
  hogar_id    uuid not null references hogares(id) on delete cascade,
  patron      text not null,           -- substring del comercio, case-insensitive
  sobre_id    uuid not null references sobres(id) on delete cascade,
  aciertos    integer not null default 0,
  creado_en   timestamptz not null default now(),
  unique (hogar_id, patron)
);

-- ============================================================
--  VISTAS DE DASHBOARD
-- ============================================================

-- Estado de cada sobre en un periodo: asignado, gastado, disponible
create view v_sobres_periodo as
select
  p.id                                   as periodo_id,
  p.hogar_id,
  s.id                                   as sobre_id,
  s.nombre,
  s.tipo,
  s.color,
  coalesce(a.monto, 0)                   as asignado,
  coalesce(a.pagado, false)              as pagado,
  coalesce(sum(m.monto), 0)              as gastado,
  coalesce(a.monto, 0) - coalesce(sum(m.monto), 0) as disponible
from periodos p
cross join sobres s
left join asignaciones a on a.periodo_id = p.id and a.sobre_id = s.id
left join movimientos  m on m.periodo_id = p.id and m.sobre_id = s.id
where s.hogar_id = p.hogar_id and s.activo
group by p.id, p.hogar_id, s.id, a.monto, a.pagado;

-- Resumen del periodo: entró, se repartió, quedó sin asignar
create view v_resumen_periodo as
select
  p.id            as periodo_id,
  p.hogar_id,
  p.inicio,
  p.fin,
  p.estado,
  coalesce((select sum(i.monto) from ingresos i where i.periodo_id = p.id), 0)      as ingreso_total,
  coalesce((select sum(a.monto) from asignaciones a where a.periodo_id = p.id), 0)  as asignado_total,
  coalesce((select sum(i.monto) from ingresos i where i.periodo_id = p.id), 0)
  - coalesce((select sum(a.monto) from asignaciones a where a.periodo_id = p.id), 0) as sin_asignar
from periodos p;

-- Base de proyección: mediana de gasto por sobre variable.
-- Mediana y no promedio: un mes con una llanta reventada no debe
-- envenenar la proyección de los seis siguientes.
create view v_base_proyeccion as
select
  s.hogar_id,
  s.id                                   as sobre_id,
  s.nombre,
  s.tipo,
  count(distinct a.periodo_id)           as periodos_con_datos,
  percentile_cont(0.5) within group (order by a.monto) as mediana_asignado,
  percentile_cont(0.8) within group (order by a.monto) as p80_asignado
from sobres s
join asignaciones a on a.sobre_id = s.id
join periodos p     on p.id = a.periodo_id and p.estado = 'cerrado'
where s.activo
group by s.hogar_id, s.id;

-- ============================================================
--  RLS — todo vive dentro del hogar
-- ============================================================
alter table hogares      enable row level security;
alter table miembros     enable row level security;
alter table periodos     enable row level security;
alter table ingresos     enable row level security;
alter table sobres       enable row level security;
alter table deudas       enable row level security;
alter table pagos_deuda  enable row level security;
alter table asignaciones enable row level security;
alter table movimientos  enable row level security;
alter table reglas       enable row level security;

create policy hogar_propio on hogares
  for all using (id = hogar_actual()) with check (id = hogar_actual());

create policy miembros_propios on miembros
  for all using (hogar_id = hogar_actual()) with check (hogar_id = hogar_actual());

-- Tablas con hogar_id directo
do $$
declare t text;
begin
  foreach t in array array['periodos','ingresos','sobres','movimientos','reglas']
  loop
    execute format(
      'create policy %I_hogar on %I for all
         using (hogar_id = hogar_actual())
         with check (hogar_id = hogar_actual())', t, t);
  end loop;
end $$;

-- Tablas que heredan el hogar vía sobre o periodo
create policy deudas_hogar on deudas for all
  using (exists (select 1 from sobres s where s.id = sobre_id and s.hogar_id = hogar_actual()))
  with check (exists (select 1 from sobres s where s.id = sobre_id and s.hogar_id = hogar_actual()));

create policy pagos_hogar on pagos_deuda for all
  using (exists (select 1 from sobres s where s.id = sobre_id and s.hogar_id = hogar_actual()))
  with check (exists (select 1 from sobres s where s.id = sobre_id and s.hogar_id = hogar_actual()));

create policy asignaciones_hogar on asignaciones for all
  using (exists (select 1 from periodos p where p.id = periodo_id and p.hogar_id = hogar_actual()))
  with check (exists (select 1 from periodos p where p.id = periodo_id and p.hogar_id = hogar_actual()));

-- ============================================================
--  AUTOMATISMOS
-- ============================================================

-- Al pagar una deuda, bajar el saldo. Sin esto el dashboard miente.
create or replace function aplicar_pago_deuda()
returns trigger language plpgsql as $$
begin
  update deudas set saldo_actual = greatest(saldo_actual - new.capital, 0)
  where sobre_id = new.sobre_id;
  return new;
end $$;

create trigger trg_pago_deuda after insert on pagos_deuda
  for each row execute function aplicar_pago_deuda();

-- Al abrir un periodo, precargar asignaciones de los sobres fijos y de deuda.
-- Ese es el 70% del reparto hecho antes de que se sienten a la mesa.
create or replace function precargar_asignaciones()
returns trigger language plpgsql as $$
begin
  insert into asignaciones (periodo_id, sobre_id, monto)
  select new.id, s.id,
         case when s.tipo = 'deuda'
              then coalesce((select d.cuota_minima from deudas d where d.sobre_id = s.id), 0)
              else coalesce(s.monto_esperado, 0) end
  from sobres s
  where s.hogar_id = new.hogar_id
    and s.activo
    and s.tipo in ('fijo','deuda')
  on conflict (periodo_id, sobre_id) do nothing;
  return new;
end $$;

create trigger trg_precargar after insert on periodos
  for each row execute function precargar_asignaciones();
