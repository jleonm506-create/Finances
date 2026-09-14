-- ============================================================
--  Sobres — tabla única de estado por usuario
--  Pegá esto completo en: Supabase → SQL Editor → New query → Run
-- ============================================================

create table if not exists estado (
  user_id        uuid primary key references auth.users(id) on delete cascade,
  datos          jsonb not null,
  actualizado_en timestamptz not null default now()
);

alter table estado enable row level security;

-- Cada usuario ve y escribe solo su propia fila.
drop policy if exists "estado propio" on estado;
create policy "estado propio" on estado
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Cuando quieras reportes con SQL, el JSON se consulta así:
--   select datos->'sobres' from estado;
--   select jsonb_array_elements(datos->'movs') from estado;
