-- Schema do Auditor de Precificação.
--
-- Reconstruído a partir do que o código realmente lê e grava (os arquivos HTML
-- são a fonte da verdade aqui, já que não havia migration versionada). Foi assim
-- que apareceu a divergência que motivou este arquivo: o código gravava
-- projetos.valor_venda, mas a coluna nunca tinha sido criada no banco remoto.

create extension if not exists "pgcrypto";

-- ── integradores ────────────────────────────────────────────────────────────
-- O "lead": empresa que preenche o funil. As colunas jsonb guardam blocos que o
-- app trata como um todo (grava e lê inteiros), então não vale normalizar.
create table if not exists public.integradores (
  id                uuid primary key default gen_random_uuid(),
  nome_empresa      text not null,
  cnpj              text,
  regime_tributario text,
  email             text,
  whatsapp          text,
  despesas          jsonb,   -- comissão, tributo, extras e despesa fixa (passo Custos)
  configs           jsonb,   -- { campos: {...}, extras: [...] } da estrutura de custos
  sazonalidade      jsonb,   -- { meses: [...] } — refinamento opcional
  criado_em         timestamptz not null default now()
);

-- ── projetos ────────────────────────────────────────────────────────────────
create table if not exists public.projetos (
  id                 uuid primary key default gen_random_uuid(),
  integrador_id      uuid references public.integradores(id) on delete cascade,
  nome_projeto       text not null,
  quantidade_modulos integer,
  kwp_sistema        numeric,
  custo_kit          numeric,
  valor_venda        numeric,   -- preço praticado hoje; alimenta o comparativo do diagnóstico
  criado_em          timestamptz not null default now()
);

-- ── orcamentos ──────────────────────────────────────────────────────────────
-- Fotografia de uma análise salva. Guarda entradas e resultados juntos de
-- propósito: o histórico precisa mostrar o número como ele era na época, mesmo
-- que os custos da empresa mudem depois.
create table if not exists public.orcamentos (
  id                      uuid primary key default gen_random_uuid(),
  integrador_id           uuid references public.integradores(id) on delete cascade,
  projeto_id              uuid references public.projetos(id) on delete set null,

  -- custos diretos do projeto
  kit                     numeric,
  ca                      numeric,
  instalacao              numeric,
  projeto                 numeric,   -- custo do projeto elétrico
  homologacao             numeric,
  art                     numeric,

  -- entradas comerciais
  ticket                  numeric,
  qtd_projetos            numeric,
  comissao_pct            numeric,
  comissao_base           text,      -- 'total' | 'servico'
  tributo_pct             numeric,
  tributo_base            text,      -- 'total' | 'servico'
  outras_pct              numeric,
  despesas_fixas          numeric,
  lucro_alvo_pct          numeric,

  -- resultados calculados
  custo_direto_total      numeric,
  faturamento_mensal      numeric,
  margem_contribuicao_pct numeric,
  lucro_mensal            numeric,
  ponto_equilibrio_qtd    numeric,
  preco_sugerido          numeric,

  criado_em               timestamptz not null default now()
);

create index if not exists idx_projetos_integrador   on public.projetos(integrador_id);
create index if not exists idx_orcamentos_integrador on public.orcamentos(integrador_id);
create index if not exists idx_orcamentos_criado_em  on public.orcamentos(criado_em desc);

-- ── Acesso ──────────────────────────────────────────────────────────────────
-- ATENÇÃO: as políticas abaixo liberam acesso ao papel anônimo porque é isso que
-- o funil exige hoje — o lead preenche tudo antes de existir qualquer login, e a
-- única chave que as páginas carregam é a publicável. Isto reproduz o
-- comportamento atual de produção para que o ambiente local seja fiel; NÃO é um
-- desenho de segurança. Restringir isso (ex.: exigir sessão para ler dados de
-- outros integradores) é tarefa própria, a ser feita junto com a decisão de
-- produto sobre quem pode ver o quê.
alter table public.integradores enable row level security;
alter table public.projetos     enable row level security;
alter table public.orcamentos   enable row level security;

-- São duas camadas independentes e ambas precisam liberar: o GRANT é a permissão
-- do Postgres sobre a tabela, a policy é o filtro linha a linha do RLS. Só a
-- policy não basta — sem GRANT o banco recusa antes de chegar no RLS.
grant usage on schema public to anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['integradores','projetos','orcamentos'] loop
    execute format('grant select, insert, update, delete on public.%I to anon, authenticated', t);
    execute format('drop policy if exists %I on public.%I', 'acesso_anon_'||t, t);
    execute format(
      'create policy %I on public.%I for all to anon, authenticated using (true) with check (true)',
      'acesso_anon_'||t, t);
  end loop;
end $$;
