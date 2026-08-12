-- Tabela diagnosticos: fotografia do relatório gerado em relatorio.html.
--
-- Diferente das outras três, esta nasce atrás de login: relatorio.html só roda
-- com sessão ativa (redireciona para login.html quando não há) e grava o id do
-- usuário junto. Por isso o acesso aqui NÃO é o mesmo das demais — cada um lê e
-- escreve as próprias linhas, e o papel anônimo não entra.
--
-- O snapshot é jsonb de propósito: guarda parâmetros e os três cenários (atual,
-- sugerido, necessário) como estavam no momento da geração. O relatório precisa
-- mostrar o número da época, mesmo que os custos da empresa mudem depois.

create table if not exists public.diagnosticos (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  integrador_id uuid references public.integradores(id) on delete set null,
  projeto_id    uuid references public.projetos(id) on delete set null,
  snapshot      jsonb not null,
  criado_em     timestamptz not null default now()
);

create index if not exists idx_diagnosticos_user      on public.diagnosticos(user_id);
create index if not exists idx_diagnosticos_criado_em on public.diagnosticos(criado_em desc);

alter table public.diagnosticos enable row level security;

-- GRANT é a permissão do Postgres sobre a tabela; a policy é o filtro linha a
-- linha do RLS. Ambos precisam liberar. Só authenticated: anon não tem user_id.
grant select, insert, update, delete on public.diagnosticos to authenticated;

drop policy if exists diagnosticos_proprios on public.diagnosticos;
create policy diagnosticos_proprios on public.diagnosticos
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
