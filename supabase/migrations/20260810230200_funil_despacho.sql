-- Despacho dos webhooks.
--
-- É aqui que o relógio realmente roda. O navegador do lead não participa: quem
-- acorda a fila é o pg_cron, de minuto em minuto, e quem faz a chamada HTTP é o
-- pg_net, de dentro do próprio Postgres.
--
-- O ciclo tem duas metades porque o pg_net é assíncrono: `despachar` enfileira a
-- requisição e guarda o id; `coletar` lê a resposta que chegou desde a última
-- passada e decide entre dar por entregue e reagendar.

-- ── funil_montar_payload ────────────────────────────────────────────────────
-- O corpo é montado na HORA do disparo, não na hora do agendamento. Um timeout
-- pode ficar duas horas na fila, e nesse intervalo o lead pode ter corrigido o
-- telefone — mandar a fotografia velha faria o time ligar para o número errado.
create or replace function public.funil_montar_payload(p_fila_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = public, extensions, pg_temp
as $$
declare
  f   public.webhook_fila;
  cfg public.funil_config;
  s   public.funil_sessoes;
  e   public.funil_etapas;
  o   public.orcamentos;
  v_base      text;
  v_link      text;
  v_resultado text;
  v_relatorio text;
begin
  select * into f   from public.webhook_fila  where id = p_fila_id;
  select * into cfg from public.funil_config  where id = 1;
  select * into s   from public.funil_sessoes where id = f.sessao_id;
  select * into e   from public.funil_etapas  where etapa = f.etapa;

  if s.orcamento_id is not null then
    select * into o from public.orcamentos where id = s.orcamento_id;
  end if;

  v_base := rtrim(coalesce(cfg.site_url, ''), '/');

  -- Dois links, e a diferença entre eles não é cosmética:
  --
  --   ?s=  é o link do LEAD. Devolve a ele o que já preencheu (a mensagem de
  --        resgate quase sempre abre em outro aparelho, com localStorage vazio)
  --        e rearma o relógio, porque abrir e mesmo assim não preencher é
  --        informação nova.
  --   ?v=  é o link do VENDEDOR, para colar no CRM. Só lê: não conta como
  --        retomada e não reinicia cadência nenhuma. Um clique interno não pode
  --        mexer no funil do lead.
  v_link      := v_base || '/' || coalesce(e.href, '') || '?s=' || s.id::text;
  v_resultado := v_base || '/?v='          || s.id::text;
  v_relatorio := v_base || '/relatorio?v=' || s.id::text;

  return jsonb_build_object(
    'evento',       f.tipo,
    'etapa',        f.etapa,
    'etapa_rotulo', e.rotulo,
    'ocorrido_em',  to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'idempotencia', f.chave_idempotencia,

    'lead', jsonb_build_object(
      'sessao',        s.id,
      'integrador_id', s.integrador_id,
      'nome_contato',  s.nome_contato,
      'nome_empresa',  s.nome_empresa,
      'cnpj',          s.cnpj,
      'email',         s.email,
      'whatsapp',      s.whatsapp,
      'whatsapp_e164', s.whatsapp_e164,
      'teste',         s.teste
    ),

    'funil', jsonb_build_object(
      'etapa_concluida', s.etapa_concluida,
      'ordem_concluida', s.ordem_concluida,
      'total_etapas',    (select count(*) from public.funil_etapas),
      'parou_em',        case when f.tipo = 'etapa.timeout' then f.etapa else null end,
      -- O que o funil está esperando do lead. Nos três primeiros timers é
      -- concluir a etapa; no último, já com o diagnóstico na tela, é o clique no
      -- WhatsApp. São dois leads em temperaturas muito diferentes e a mensagem
      -- de cada um não pode ser a mesma — por isso a distinção vem pronta.
      'aguardando',      case
                           when f.tipo <> 'etapa.timeout'            then null
                           when f.ordem_referencia >= e.ordem        then 'cta_whatsapp'
                           else 'etapa'
                         end,
      'concluiu',        s.concluido_em is not null,
      'cta_clicado',     s.cta_clicado_em is not null,
      'criado_em',       s.criado_em,
      'atualizado_em',   s.atualizado_em,
      'minutos_parado',  round(extract(epoch from (now() - s.atualizado_em)) / 60)
    ),

    'origem',      s.origem,
    'dados',       s.dados,
    'diagnostico', case when o.id is null then null else to_jsonb(o) end,

    'links', jsonb_build_object(
      -- Para a mensagem que vai AO LEAD.
      'retomar',   v_link,
      -- Para gravar no card do CRM: é por aqui que o vendedor vê os números do
      -- lead antes de falar com ele. Vale mesmo com o funil pela metade — a tela
      -- mostra o que já foi preenchido e para onde o lead ainda não foi.
      'resultado', v_resultado,
      'relatorio', v_relatorio,
      -- Só depois do diagnóstico o relatório tem conteúdo completo.
      'resultado_completo', s.concluido_em is not null
    )
  );
end;
$$;

-- ── funil_despachar_webhooks ────────────────────────────────────────────────
create or replace function public.funil_despachar_webhooks(p_lote int default 25)
returns int
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  f   public.webhook_fila;
  cfg public.funil_config;
  s   public.funil_sessoes;
  e   public.funil_etapas;
  v_url     text;
  v_payload jsonb;
  v_corpo   text;
  v_req     bigint;
  v_n       int := 0;
begin
  select * into cfg from public.funil_config where id = 1;

  -- skip locked: se duas execuções do cron se sobrepuserem (uma passada lenta),
  -- a segunda pula as linhas que a primeira já pegou em vez de disparar de novo.
  for f in
    select * from public.webhook_fila
     where status = 'pendente' and agendado_para <= now()
     order by agendado_para
     for update skip locked
     limit p_lote
  loop
    select * into s from public.funil_sessoes where id = f.sessao_id;
    select * into e from public.funil_etapas  where etapa = f.etapa;

    -- Revalidação do timeout. Entre o agendamento e agora o lead pode ter
    -- avançado por conta própria e a linha ainda não ter sido cancelada (ou o
    -- cancelamento ter perdido a corrida). Cobrar quem já avançou é o pior erro
    -- que este sistema pode cometer, então a checagem é refeita na hora.
    --
    -- O teste é contra `ordem_referencia`, o ponto em que o lead estava quando o
    -- relógio começou: se ele saiu de lá, avançou. Comparar com a etapa esperada
    -- daria falso positivo no último timer, que espera um clique e não uma etapa.
    if f.tipo = 'etapa.timeout' then
      if s.id is null
         or s.ordem_concluida > coalesce(f.ordem_referencia, -1)
         or s.cta_clicado_em is not null
         or not coalesce(e.ativo, false) then
        update public.webhook_fila
           set status = 'cancelado', erro = 'lead avançou ou etapa desativada'
         where id = f.id;
        continue;
      end if;
    end if;

    v_url := case
      when f.url is not null and f.url <> '' then f.url
      when f.tipo = 'etapa.timeout'          then e.webhook_url
      else cfg.webhook_url_eventos
    end;

    if v_url is null or v_url = '' then
      update public.webhook_fila
         set status = 'cancelado', erro = 'sem URL de webhook configurada'
       where id = f.id;
      continue;
    end if;

    v_payload := coalesce(f.payload, public.funil_montar_payload(f.id));
    v_corpo   := v_payload::text;

    -- A assinatura cobre o corpo exatamente como ele vai na requisição. Do outro
    -- lado, o n8n recalcula o HMAC sobre os bytes crus recebidos e compara — é o
    -- que impede que qualquer um que descubra a URL injete leads falsos.
    v_req := net.http_post(
      url     := v_url,
      body    := v_payload,
      headers := jsonb_build_object(
        'Content-Type',        'application/json',
        'X-Funil-Evento',      f.tipo,
        'X-Funil-Idempotencia', coalesce(f.chave_idempotencia, f.id::text),
        'X-Funil-Assinatura',  'sha256=' || encode(hmac(v_corpo, cfg.webhook_segredo, 'sha256'), 'hex')
      ),
      timeout_milliseconds := 10000
    );

    update public.webhook_fila
       set status        = 'enviando',
           request_id    = v_req,
           payload       = v_payload,
           url           = v_url,
           despachado_em = now(),
           tentativas    = tentativas + 1
     where id = f.id;

    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$$;

-- ── funil_coletar_respostas ─────────────────────────────────────────────────
-- O pg_net guarda a resposta em net._http_response e a limpa sozinho depois de
-- algumas horas. Rodando a cada minuto isso nunca é apertado; a cláusula de
-- reciclagem no fim cobre o caso raro da resposta ter sumido antes da leitura.
create or replace function public.funil_coletar_respostas()
returns int
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  f   public.webhook_fila;
  cfg public.funil_config;
  r   record;
  v_n int := 0;
begin
  select * into cfg from public.funil_config where id = 1;

  for f in
    select * from public.webhook_fila
     where status = 'enviando' and request_id is not null
     for update skip locked
  loop
    select status_code, content, error_msg, timed_out
      into r
      from net._http_response
     where id = f.request_id;

    if not found then
      -- Resposta ainda não chegou (ou já foi expurgada). Se está pendurada há
      -- mais de 15 minutos DESDE O ENVIO, trata como falha e deixa o retry
      -- decidir. Medir a partir de `criado_em` daria falso positivo em todo
      -- timeout, que por natureza espera horas antes de sair.
      if coalesce(f.despachado_em, f.criado_em) < now() - interval '15 minutes' then
        perform public.funil_falhar_webhook(f.id, null, 'sem resposta do pg_net', cfg.webhook_max_tentativas);
      end if;
      continue;
    end if;

    if r.status_code between 200 and 299 then
      update public.webhook_fila
         set status = 'enviado', http_status = r.status_code,
             resposta = left(coalesce(r.content, ''), 2000), erro = null,
             enviado_em = now()
       where id = f.id;
    else
      perform public.funil_falhar_webhook(
        f.id, r.status_code,
        coalesce(nullif(r.error_msg, ''),
                 case when r.timed_out then 'timeout' else left(coalesce(r.content,''), 500) end),
        cfg.webhook_max_tentativas);
    end if;

    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$$;

-- ── funil_falhar_webhook ────────────────────────────────────────────────────
-- Backoff crescente. O n8n cair por dez minutos não pode custar o lead, mas
-- insistir para sempre em uma URL errada só enche a fila — daí o teto.
create or replace function public.funil_falhar_webhook(
  p_id          uuid,
  p_http        int,
  p_erro        text,
  p_max         int
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tent int;
begin
  select tentativas into v_tent from public.webhook_fila where id = p_id;

  if v_tent >= p_max then
    update public.webhook_fila
       set status = 'falhou', http_status = p_http, erro = p_erro, request_id = null
     where id = p_id;
    return;
  end if;

  update public.webhook_fila
     set status        = 'pendente',
         http_status   = p_http,
         erro          = p_erro,
         request_id    = null,
         agendado_para = now() + case v_tent
                                   when 1 then interval '1 minute'
                                   when 2 then interval '5 minutes'
                                   when 3 then interval '15 minutes'
                                   when 4 then interval '1 hour'
                                   else        interval '6 hours'
                                 end
   where id = p_id;
end;
$$;

-- ── Limpeza ─────────────────────────────────────────────────────────────────
-- A fila é histórico útil para depurar com o time de automação, mas não para
-- sempre. 90 dias cobre qualquer investigação real.
create or replace function public.funil_limpar_fila()
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  delete from public.webhook_fila
   where status in ('enviado','cancelado')
     and criado_em < now() - interval '90 days';
$$;

-- ── Agendamento ─────────────────────────────────────────────────────────────
-- Um minuto é a menor granularidade do pg_cron e é folgada para tempos medidos
-- em dezenas de minutos: o atraso máximo de um disparo é de 59 segundos.
select cron.unschedule('funil-webhooks')
 where exists (select 1 from cron.job where jobname = 'funil-webhooks');

select cron.schedule(
  'funil-webhooks', '* * * * *',
  $$ select public.funil_coletar_respostas(); select public.funil_despachar_webhooks(); $$
);

select cron.unschedule('funil-limpeza')
 where exists (select 1 from cron.job where jobname = 'funil-limpeza');

select cron.schedule('funil-limpeza', '17 4 * * *', $$ select public.funil_limpar_fila(); $$);

-- Nenhuma destas é superfície pública: só o cron (que roda como superusuário do
-- job) e o /adm, através das funções adm_*, chegam aqui.
revoke execute on function public.funil_montar_payload(uuid)            from public;
revoke execute on function public.funil_despachar_webhooks(int)         from public;
revoke execute on function public.funil_coletar_respostas()             from public;
revoke execute on function public.funil_falhar_webhook(uuid,int,text,int) from public;
revoke execute on function public.funil_limpar_fila()                   from public;
