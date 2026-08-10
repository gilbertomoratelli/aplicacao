-- Rastreamento do funil de captação.
--
-- O funil era cego para abandono: o estado vivia no localStorage e o banco só
-- recebia uma gravação best-effort, então quem parava no meio simplesmente
-- sumia. Estas tabelas dão ao funil uma identidade de sessão própria e uma fila
-- de saída (outbox) para avisar o n8n quando o lead avança ou quando para.
--
-- A ideia central é o outbox: ao concluir uma etapa, agenda-se o disparo do
-- timeout da etapa SEGUINTE para daqui a N segundos. Se o lead avançar antes, a
-- linha é cancelada; se não avançar, o cron encontra a linha vencida e dispara.
-- É isso que faz o relógio continuar rodando com o navegador do lead fechado.

-- pg_net faz a chamada HTTP a partir do próprio Postgres; pg_cron acorda a fila
-- de minuto em minuto. Se o `create extension` falhar por permissão no projeto
-- remoto, ligue os dois em Database → Extensions no painel do Supabase e rode a
-- migration de novo: o `if not exists` torna o passo idempotente.
create extension if not exists pgcrypto;
create extension if not exists pg_net;
create extension if not exists pg_cron;

-- ── funil_config ────────────────────────────────────────────────────────────
-- Linha única. É o que o /adm edita e o que o funil lê para saber para onde
-- mandar o lead no fim.
create table if not exists public.funil_config (
  id                    int primary key default 1 check (id = 1),
  cta_whatsapp          text,
  -- Raiz pública do site. Serve para montar o link de retomada que vai dentro do
  -- webhook; o Postgres não tem como descobrir sozinho por onde o lead entrou.
  site_url              text not null default 'https://grupofavo.com/precificacao',
  -- Os eventos positivos (avançou, concluiu, clicou no CTA) são um fluxo só:
  -- servem para manter o CRM em dia e para o n8n CANCELAR a cadência quando o
  -- lead volta sozinho. Por isso têm um destino único, e não um por etapa como
  -- os timeouts — que são quatro cadências de reengajamento diferentes.
  webhook_url_eventos   text,
  -- Chave do HMAC que assina o corpo de cada webhook. Nasce aleatória e é
  -- rotacionável pelo /adm; nunca sai daqui para o navegador.
  webhook_segredo       text not null default encode(gen_random_bytes(32), 'hex'),
  webhook_max_tentativas int not null default 5,
  atualizado_em         timestamptz not null default now()
);

insert into public.funil_config (id) values (1) on conflict (id) do nothing;

-- ── funil_etapas ────────────────────────────────────────────────────────────
-- Uma linha por etapa do funil, na mesma ordem de AppCore.PASSOS (app-core.js).
-- `timeout_segundos` da etapa N é o tempo máximo para CONCLUIR a etapa N,
-- contado de quando o lead chegou nela (ou seja, de quando concluiu a N-1).
create table if not exists public.funil_etapas (
  etapa            text primary key,
  ordem            int  not null unique,
  rotulo           text not null,
  -- Mesmo caminho de AppCore.PASSOS[].href. Fica aqui porque o link de retomada
  -- que vai no webhook é montado no banco, e ele precisa saber para qual página
  -- mandar o lead de volta.
  href             text not null,
  timeout_segundos int  not null default 3600 check (timeout_segundos > 0),
  webhook_url      text,
  ativo            boolean not null default true,
  nota             text,
  atualizado_em    timestamptz not null default now()
);

insert into public.funil_etapas (etapa, ordem, rotulo, href, timeout_segundos, ativo, nota) values
  ('contato',     1,  'Contato',     'cadastro',  900, false,
   'A sessão do lead só nasce quando ele conclui esta etapa — antes disso não há nome nem WhatsApp para contatar. Este tempo só vale para quem volta por um link de recuperação e para de novo aqui.'),
  ('projeto',     2,  'Projeto',     'projeto',  1800, true,  null),
  ('custos',      3,  'Custos',      'custos',   3600, true,  null),
  ('diagnostico', 4,  'Diagnóstico', '',         7200, true,
   'Aqui o lead já viu o diagnóstico. O tempo conta até ele clicar no CTA do WhatsApp; é o lead mais quente do funil.')
on conflict (etapa) do nothing;

-- ── funil_sessoes ───────────────────────────────────────────────────────────
-- A jornada de um lead. O `id` é o token que o navegador guarda em
-- localStorage.funilSessao e que volta no link de recuperação (?s=).
--
-- O contato aparece desnormalizado de propósito: o /adm e o payload do webhook
-- precisam de nome e WhatsApp em toda linha, e fazer join com `integradores`
-- para isso não paga o custo — ainda mais porque a sessão pode existir antes de
-- o integrador estar completo.
create table if not exists public.funil_sessoes (
  id               uuid primary key default gen_random_uuid(),
  integrador_id    uuid references public.integradores(id) on delete set null,
  projeto_id       uuid references public.projetos(id)     on delete set null,
  -- Uma sessão tem um projeto e um conjunto de custos, logo tem UM diagnóstico.
  -- Guardar o id aqui faz o recarregamento da página de diagnóstico atualizar a
  -- linha em vez de criar outra — hoje cada F5 duplica o registro no histórico.
  orcamento_id     uuid references public.orcamentos(id)   on delete set null,

  etapa_concluida  text references public.funil_etapas(etapa),
  ordem_concluida  int  not null default 0,

  nome_contato     text,
  nome_empresa     text,
  cnpj             text,
  email            text,
  whatsapp         text,
  whatsapp_e164    text,

  -- Snapshot acumulado do que o lead preencheu, etapa a etapa. Serve para
  -- reidratar o localStorage quando ele volta em outro dispositivo.
  dados            jsonb not null default '{}'::jsonb,
  -- utm_*, referrer, user agent e primeiro acesso. Gravado uma vez só.
  origem           jsonb not null default '{}'::jsonb,

  teste            boolean not null default false,

  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  concluido_em     timestamptz,
  cta_clicado_em   timestamptz
);

create index if not exists idx_funil_sessoes_atualizado on public.funil_sessoes(atualizado_em desc);
create index if not exists idx_funil_sessoes_etapa      on public.funil_sessoes(etapa_concluida);
create index if not exists idx_funil_sessoes_whatsapp   on public.funil_sessoes(whatsapp_e164);
create index if not exists idx_funil_sessoes_integrador on public.funil_sessoes(integrador_id);

-- ── funil_eventos ───────────────────────────────────────────────────────────
-- Append-only. É o log de auditoria da jornada: dá para reconstruir exatamente
-- quando cada etapa foi concluída, mesmo depois de a sessão ser atualizada.
create table if not exists public.funil_eventos (
  id        bigserial primary key,
  sessao_id uuid not null references public.funil_sessoes(id) on delete cascade,
  tipo      text not null,
  etapa     text,
  payload   jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now()
);

create index if not exists idx_funil_eventos_sessao on public.funil_eventos(sessao_id, criado_em desc);

-- ── webhook_fila ────────────────────────────────────────────────────────────
-- O outbox. `agendado_para` no futuro = timeout armado; `agendado_para = now()`
-- = evento imediato. `payload` fica nulo porque é montado na hora do disparo,
-- com o estado atual do lead — assim um timeout que ficou 2h na fila não envia
-- uma fotografia velha.
create table if not exists public.webhook_fila (
  id                  uuid primary key default gen_random_uuid(),
  sessao_id           uuid references public.funil_sessoes(id) on delete cascade,
  etapa               text,
  tipo                text not null,   -- etapa.timeout | etapa.concluida | funil.concluido | cta.clicado | webhook.teste
  -- Em que ponto do funil o lead estava quando este timeout foi armado. É o que
  -- define se ele ainda vale na hora do disparo: se `ordem_concluida` andou
  -- além disto, o lead avançou sozinho e não há nada a cobrar. Guardar o ponto
  -- de partida (e não a etapa esperada) resolve também o último timer, que
  -- espera um clique no CTA e não a conclusão de uma etapa seguinte.
  ordem_referencia    int,
  url                 text,
  payload             jsonb,
  agendado_para       timestamptz not null default now(),
  status              text not null default 'pendente'
                      check (status in ('pendente','enviando','enviado','cancelado','falhou')),
  tentativas          int  not null default 0,
  request_id          bigint,
  http_status         int,
  resposta            text,
  erro                text,
  chave_idempotencia  text unique,
  criado_em           timestamptz not null default now(),
  -- Quando a requisição saiu. É diferente de `criado_em`: um timeout fica horas
  -- na fila antes de sair, e a espera pela resposta do pg_net conta a partir do
  -- envio, não do agendamento.
  despachado_em       timestamptz,
  enviado_em          timestamptz
);

-- Índice parcial: o cron só pergunta por pendentes vencidos, e a fila inteira
-- (incluindo o histórico de enviados) não precisa ser varrida para isso.
create index if not exists idx_webhook_fila_pendente
  on public.webhook_fila(agendado_para) where status = 'pendente';
create index if not exists idx_webhook_fila_enviando
  on public.webhook_fila(request_id) where status = 'enviando';
create index if not exists idx_webhook_fila_sessao
  on public.webhook_fila(sessao_id, criado_em desc);

-- ── Acesso ──────────────────────────────────────────────────────────────────
-- RLS ligado e NENHUMA policy: `anon` e `authenticated` não enxergam estas
-- tabelas de forma alguma. Toda leitura e escrita passa pelas funções
-- `security definer` das próximas migrations, que rodam como dono e por isso
-- não esbarram no RLS. Sem GRANT, o PostgREST nem chega a tentar.
alter table public.funil_config  enable row level security;
alter table public.funil_etapas  enable row level security;
alter table public.funil_sessoes enable row level security;
alter table public.funil_eventos enable row level security;
alter table public.webhook_fila  enable row level security;

revoke all on public.funil_config, public.funil_etapas, public.funil_sessoes,
              public.funil_eventos, public.webhook_fila
  from anon, authenticated;

-- ── Auxiliar: WhatsApp em E.164 ─────────────────────────────────────────────
-- A chave de deduplicação do lead no CRM é o telefone, e "(11) 98765-4321",
-- "11987654321" e "+55 11 98765-4321" são a mesma pessoa. Normalizar aqui, uma
-- vez, evita que cada consumidor do webhook invente a própria regra.
-- Devolve null quando não dá para afirmar com confiança qual é o número.
create or replace function public.funil_normalizar_whatsapp(p_valor text)
returns text
language plpgsql
immutable
as $$
declare
  d text;
begin
  if p_valor is null then return null; end if;
  d := regexp_replace(p_valor, '\D', '', 'g');

  -- 10 dígitos = DDD + fixo; 11 = DDD + celular com o 9. Ambos são nacionais.
  if length(d) in (10, 11) then
    return '+55' || d;
  end if;

  -- Já veio com o código do país.
  if length(d) in (12, 13) and left(d, 2) = '55' then
    return '+' || d;
  end if;

  return null;
end;
$$;

comment on table  public.funil_sessoes is 'Jornada de um lead pelo funil. O id é o token de recuperação (?s=).';
comment on table  public.webhook_fila  is 'Outbox de webhooks. agendado_para no futuro = timeout armado.';
comment on column public.funil_etapas.timeout_segundos is 'Tempo máximo para concluir esta etapa, contado de quando o lead chegou nela.';
