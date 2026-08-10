-- Superfície pública do funil.
--
-- Estas funções são a ÚNICA porta que o navegador tem para o banco. As tabelas
-- não têm GRANT para `anon`; as funções são `security definer`, então rodam como
-- dono e atravessam o RLS. O ganho não é só de segurança: a regra de negócio
-- (o que conta como progresso, quando armar e quando cancelar um timeout) fica
-- em um lugar só, e não espalhada por quatro páginas HTML que podem divergir.
--
-- `set search_path` fixo em toda função é obrigatório com security definer: sem
-- isso, quem chama pode plantar um schema no search_path e sequestrar a
-- resolução de nomes dentro da função.

-- ── funil_config_publica ────────────────────────────────────────────────────
-- O navegador precisa saber para onde mandar o lead no fim. Só isso. Devolver a
-- linha inteira vazaria as URLs de webhook e o segredo do HMAC para qualquer
-- visitante, então a projeção é explícita e mínima.
create or replace function public.funil_config_publica()
returns jsonb
language sql
security definer
stable
set search_path = public, pg_temp
as $$
  select jsonb_build_object('cta_whatsapp', coalesce(cta_whatsapp, ''))
  from public.funil_config where id = 1;
$$;

-- ── funil_registrar_etapa ───────────────────────────────────────────────────
-- Chamada ao concluir cada etapa do funil. Faz, em uma transação:
--   1. localiza ou cria a sessão
--   2. grava nas tabelas de negócio (integradores / projetos / orcamentos)
--   3. acumula o snapshot em funil_sessoes.dados
--   4. registra o evento
--   5. cancela o timeout desta etapa e das anteriores
--   6. arma o timeout da próxima
--   7. enfileira os eventos positivos
--
-- p_integrador_id / p_projeto_id existem para adotar os ids que já estão no
-- localStorage de quem começou o funil antes desta mudança — sem eles, esses
-- leads virariam registros duplicados na primeira etapa que concluíssem.
create or replace function public.funil_registrar_etapa(
  p_etapa         text,
  p_dados         jsonb default '{}'::jsonb,
  p_sessao        uuid  default null,
  p_origem        jsonb default null,
  p_integrador_id uuid  default null,
  p_projeto_id    uuid  default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_sessao   public.funil_sessoes;
  v_etapa    public.funil_etapas;
  v_prox     public.funil_etapas;
  v_orc      public.orcamentos;
  v_dados    jsonb := coalesce(p_dados, '{}'::jsonb);
  v_int_id   uuid;
  v_proj_id  uuid;
  v_orc_id   uuid;
  v_evento   bigint;
  v_ordem    int;
  v_etapa_c  text;
  v_whats    text;
  v_int      public.integradores;
begin
  select * into v_etapa from public.funil_etapas where etapa = p_etapa;
  if not found then
    raise exception 'Etapa desconhecida: %', p_etapa using errcode = '22023';
  end if;

  -- 1. Sessão -----------------------------------------------------------------
  if p_sessao is not null then
    select * into v_sessao from public.funil_sessoes where id = p_sessao for update;
  end if;

  if v_sessao.id is null then
    insert into public.funil_sessoes (integrador_id, projeto_id, origem)
    values (
      (select id from public.integradores where id = p_integrador_id),
      (select id from public.projetos     where id = p_projeto_id),
      coalesce(p_origem, '{}'::jsonb)
    )
    returning * into v_sessao;
  elsif p_origem is not null and v_sessao.origem = '{}'::jsonb then
    -- A origem é de onde o lead VEIO; gravar só na primeira vez impede que uma
    -- volta pelo link de recuperação apague a campanha que realmente o trouxe.
    update public.funil_sessoes set origem = p_origem
     where id = v_sessao.id returning * into v_sessao;
  end if;

  v_int_id  := v_sessao.integrador_id;
  v_proj_id := v_sessao.projeto_id;
  v_orc_id  := v_sessao.orcamento_id;

  -- 2. Tabelas de negócio -----------------------------------------------------
  if p_etapa = 'contato' then
    if v_int_id is not null then
      update public.integradores set
        nome_contato      = coalesce(nullif(v_dados->>'nome_contato',''),      nome_contato),
        nome_empresa      = coalesce(nullif(v_dados->>'nome_empresa',''),      nome_empresa),
        cnpj              = coalesce(nullif(v_dados->>'cnpj',''),              cnpj),
        email             = coalesce(nullif(v_dados->>'email',''),             email),
        whatsapp          = coalesce(nullif(v_dados->>'whatsapp',''),          whatsapp),
        regime_tributario = coalesce(nullif(v_dados->>'regime_tributario',''), regime_tributario)
      where id = v_int_id;
      -- Id de outro ambiente no localStorage: a linha não existe aqui, então
      -- cai para o insert em vez de perder a etapa em silêncio.
      if not found then v_int_id := null; end if;
    end if;

    if v_int_id is null then
      insert into public.integradores (nome_contato, nome_empresa, cnpj, email, whatsapp, regime_tributario)
      values (
        nullif(v_dados->>'nome_contato',''),
        coalesce(nullif(v_dados->>'nome_empresa',''), 'Empresa sem nome'),
        nullif(v_dados->>'cnpj',''),
        nullif(v_dados->>'email',''),
        nullif(v_dados->>'whatsapp',''),
        nullif(v_dados->>'regime_tributario','')
      )
      returning id into v_int_id;
    end if;

  elsif p_etapa = 'projeto' then
    if v_proj_id is not null then
      update public.projetos set
        integrador_id      = coalesce(v_int_id, integrador_id),
        nome_projeto       = coalesce(nullif(v_dados->>'nome_projeto',''), nome_projeto),
        quantidade_modulos = coalesce((v_dados->>'quantidade_modulos')::int,     quantidade_modulos),
        kwp_sistema        = coalesce((v_dados->>'kwp_sistema')::numeric,        kwp_sistema),
        custo_kit          = coalesce((v_dados->>'custo_kit')::numeric,          custo_kit),
        valor_venda        = coalesce((v_dados->>'valor_venda')::numeric,        valor_venda)
      where id = v_proj_id;
      if not found then v_proj_id := null; end if;
    end if;

    if v_proj_id is null then
      insert into public.projetos (integrador_id, nome_projeto, quantidade_modulos, kwp_sistema, custo_kit, valor_venda)
      values (
        v_int_id,
        coalesce(nullif(v_dados->>'nome_projeto',''), 'Projeto sem medidas'),
        (v_dados->>'quantidade_modulos')::int,
        (v_dados->>'kwp_sistema')::numeric,
        (v_dados->>'custo_kit')::numeric,
        (v_dados->>'valor_venda')::numeric
      )
      returning id into v_proj_id;
    end if;

  elsif p_etapa = 'custos' then
    if v_int_id is not null then
      update public.integradores set
        despesas          = coalesce(nullif(v_dados->'despesas', 'null'::jsonb), despesas),
        configs           = coalesce(nullif(v_dados->'configs',  'null'::jsonb), configs),
        regime_tributario = coalesce(nullif(v_dados->>'regime_tributario',''),   regime_tributario)
      where id = v_int_id;
    end if;

  elsif p_etapa = 'diagnostico' then
    if jsonb_typeof(v_dados->'orcamento') = 'object' then
      select * into v_orc
        from jsonb_populate_record(null::public.orcamentos, v_dados->'orcamento');

      -- Uma sessão, um diagnóstico: o F5 na tela de resultado atualiza a linha
      -- em vez de empilhar cópias no histórico.
      insert into public.orcamentos (
        id, integrador_id, projeto_id,
        kit, ca, instalacao, projeto, homologacao, art,
        ticket, qtd_projetos, comissao_pct, comissao_base, tributo_pct, tributo_base,
        outras_pct, despesas_fixas, lucro_alvo_pct,
        custo_direto_total, faturamento_mensal, margem_contribuicao_pct,
        lucro_mensal, ponto_equilibrio_qtd, preco_sugerido
      ) values (
        coalesce(v_orc_id, gen_random_uuid()), v_int_id, v_proj_id,
        v_orc.kit, v_orc.ca, v_orc.instalacao, v_orc.projeto, v_orc.homologacao, v_orc.art,
        v_orc.ticket, v_orc.qtd_projetos, v_orc.comissao_pct, v_orc.comissao_base,
        v_orc.tributo_pct, v_orc.tributo_base,
        v_orc.outras_pct, v_orc.despesas_fixas, v_orc.lucro_alvo_pct,
        v_orc.custo_direto_total, v_orc.faturamento_mensal, v_orc.margem_contribuicao_pct,
        v_orc.lucro_mensal, v_orc.ponto_equilibrio_qtd, v_orc.preco_sugerido
      )
      on conflict (id) do update set
        integrador_id           = excluded.integrador_id,
        projeto_id              = excluded.projeto_id,
        kit                     = excluded.kit,
        ca                      = excluded.ca,
        instalacao              = excluded.instalacao,
        projeto                 = excluded.projeto,
        homologacao             = excluded.homologacao,
        art                     = excluded.art,
        ticket                  = excluded.ticket,
        qtd_projetos            = excluded.qtd_projetos,
        comissao_pct            = excluded.comissao_pct,
        comissao_base           = excluded.comissao_base,
        tributo_pct             = excluded.tributo_pct,
        tributo_base            = excluded.tributo_base,
        outras_pct              = excluded.outras_pct,
        despesas_fixas          = excluded.despesas_fixas,
        lucro_alvo_pct          = excluded.lucro_alvo_pct,
        custo_direto_total      = excluded.custo_direto_total,
        faturamento_mensal      = excluded.faturamento_mensal,
        margem_contribuicao_pct = excluded.margem_contribuicao_pct,
        lucro_mensal            = excluded.lucro_mensal,
        ponto_equilibrio_qtd    = excluded.ponto_equilibrio_qtd,
        preco_sugerido          = excluded.preco_sugerido
      returning id into v_orc_id;
    end if;
  end if;

  -- 3. Sessão: snapshot, contato e progresso ----------------------------------
  -- Quem já estava no meio do funil quando isto entrou no ar chega aqui sem
  -- nunca ter passado pela etapa de contato: a sessão nasceria sem nome e sem
  -- telefone, e o webhook sairia sem ninguém para o time contatar. O integrador
  -- adotado pelo id do localStorage tem esses dados — basta buscá-los.
  if v_int_id is not null then
    select * into v_int from public.integradores where id = v_int_id;
  end if;

  -- Voltar para corrigir o contato não pode rebaixar quem já está na etapa 3:
  -- o progresso só anda para frente.
  if v_etapa.ordem > v_sessao.ordem_concluida then
    v_ordem   := v_etapa.ordem;
    v_etapa_c := p_etapa;
  else
    v_ordem   := v_sessao.ordem_concluida;
    v_etapa_c := v_sessao.etapa_concluida;
  end if;

  -- Ordem de precedência: o que a etapa acabou de informar, depois o que a
  -- sessão já tinha, e só então o integrador — que pode estar desatualizado.
  v_whats := coalesce(nullif(v_dados->>'whatsapp',''), v_sessao.whatsapp, v_int.whatsapp);

  update public.funil_sessoes set
    integrador_id   = v_int_id,
    projeto_id      = v_proj_id,
    orcamento_id    = v_orc_id,
    etapa_concluida = v_etapa_c,
    ordem_concluida = v_ordem,
    nome_contato    = coalesce(nullif(v_dados->>'nome_contato',''), nome_contato, v_int.nome_contato),
    nome_empresa    = coalesce(nullif(v_dados->>'nome_empresa',''), nome_empresa, v_int.nome_empresa),
    cnpj            = coalesce(nullif(v_dados->>'cnpj',''),         cnpj,         v_int.cnpj),
    email           = coalesce(nullif(v_dados->>'email',''),        email,        v_int.email),
    whatsapp        = v_whats,
    whatsapp_e164   = public.funil_normalizar_whatsapp(v_whats),
    dados           = dados || jsonb_build_object(p_etapa, v_dados),
    atualizado_em   = now(),
    concluido_em    = case when p_etapa = 'diagnostico' then coalesce(concluido_em, now()) else concluido_em end
  where id = v_sessao.id
  returning * into v_sessao;

  -- 4. Evento -----------------------------------------------------------------
  insert into public.funil_eventos (sessao_id, tipo, etapa, payload)
  values (v_sessao.id, 'etapa.concluida', p_etapa, v_dados)
  returning id into v_evento;

  -- 5. Cancela os timeouts que esta conclusão tornou obsoletos -----------------
  -- Obsoleto = armado quando o lead estava mais atrás do que está agora.
  update public.webhook_fila w set status = 'cancelado'
   where w.sessao_id = v_sessao.id
     and w.tipo   = 'etapa.timeout'
     and w.status = 'pendente'
     and coalesce(w.ordem_referencia, 0) < v_ordem;

  -- 6. Arma o próximo timeout -------------------------------------------------
  -- Enquanto há etapa adiante, o relógio conta até ela ser concluída. Na última
  -- etapa não há "próxima": ali o que se espera do lead é o clique no CTA, e é
  -- esse o lead mais quente do funil — deixá-lo sem relógio seria perder
  -- justamente quem viu os próprios números e hesitou.
  --
  -- A URL não é resolvida aqui de propósito: se o webhook for configurado
  -- depois, os timeouts já armados passam a valer sem precisar refazer nada.
  select * into v_prox from public.funil_etapas
   where ordem > v_ordem and ativo order by ordem limit 1;

  if not found and v_sessao.cta_clicado_em is null then
    select * into v_prox from public.funil_etapas where ordem = v_ordem and ativo;
  end if;

  if v_prox.etapa is not null then
    insert into public.webhook_fila (sessao_id, etapa, tipo, agendado_para, ordem_referencia, chave_idempotencia)
    values (
      v_sessao.id, v_prox.etapa, 'etapa.timeout',
      now() + make_interval(secs => v_prox.timeout_segundos),
      v_ordem,
      v_sessao.id::text || ':timeout:' || v_prox.etapa
    )
    -- Rearma um timeout que já tinha sido cancelado (lead que vai e volta pelo
    -- funil), mas não mexe em um que ainda está pendente — o `where` faz o
    -- ON CONFLICT virar no-op nesse caso, sem duplicar linha nem reiniciar um
    -- relógio que já está correndo (o F5 na tela de diagnóstico cai aqui).
    on conflict (chave_idempotencia) do update set
      status           = 'pendente',
      agendado_para    = excluded.agendado_para,
      ordem_referencia = excluded.ordem_referencia,
      tentativas       = 0,
      request_id       = null,
      http_status      = null,
      resposta         = null,
      erro             = null,
      despachado_em    = null,
      enviado_em       = null
    where public.webhook_fila.status <> 'pendente';
  end if;

  -- 7. Eventos positivos ------------------------------------------------------
  -- A chave inclui o id do evento: `etapa.concluida` é um acontecimento, não um
  -- estado, e precisa chegar toda vez. É esse webhook que o n8n usa para parar
  -- uma cadência quando o lead volta sozinho — perder um é pior que repetir um.
  insert into public.webhook_fila (sessao_id, etapa, tipo, chave_idempotencia)
  values (v_sessao.id, p_etapa, 'etapa.concluida',
          v_sessao.id::text || ':concluida:' || v_evento::text);

  if p_etapa = 'diagnostico' then
    insert into public.webhook_fila (sessao_id, etapa, tipo, chave_idempotencia)
    values (v_sessao.id, p_etapa, 'funil.concluido', v_sessao.id::text || ':funil.concluido')
    on conflict (chave_idempotencia) do nothing;
  end if;

  return jsonb_build_object(
    'sessao',        v_sessao.id,
    'integrador_id', v_int_id,
    'projeto_id',    v_proj_id,
    'orcamento_id',  v_orc_id
  );
end;
$$;

-- ── funil_registrar_cta ─────────────────────────────────────────────────────
-- O clique no botão de WhatsApp é a conversão do funil. Cancela o timeout do
-- diagnóstico (não faz sentido cobrar quem já foi conversar) e avisa o n8n na
-- hora, porque a partir daqui o lead vira atendimento humano.
create or replace function public.funil_registrar_cta(p_sessao uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_sessao public.funil_sessoes;
begin
  select * into v_sessao from public.funil_sessoes where id = p_sessao for update;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'sessao inexistente');
  end if;

  update public.funil_sessoes
     set cta_clicado_em = coalesce(cta_clicado_em, now()),
         atualizado_em  = now()
   where id = v_sessao.id;

  insert into public.funil_eventos (sessao_id, tipo, etapa)
  values (v_sessao.id, 'cta.clicado', v_sessao.etapa_concluida);

  update public.webhook_fila set status = 'cancelado'
   where sessao_id = v_sessao.id and tipo = 'etapa.timeout' and status = 'pendente';

  insert into public.webhook_fila (sessao_id, etapa, tipo, chave_idempotencia)
  values (v_sessao.id, v_sessao.etapa_concluida, 'cta.clicado',
          v_sessao.id::text || ':cta.clicado')
  on conflict (chave_idempotencia) do nothing;

  return jsonb_build_object('ok', true);
end;
$$;

-- ── funil_retomar ───────────────────────────────────────────────────────────
-- O link de recuperação (?s=<uuid>) chega pelo WhatsApp e normalmente abre em
-- OUTRO dispositivo, onde o localStorage está vazio. Sem isto o lead recomeça do
-- zero e abandona de novo — a mensagem de resgate acaba piorando o funil.
--
-- Rearma o timeout da etapa em que ele está parado: se ele abriu o link e mesmo
-- assim não preencheu, isso é informação nova e merece um novo toque.
--
-- p_consulta muda tudo isso. O mesmo mecanismo serve ao VENDEDOR, que abre pelo
-- CRM o link do resultado para ver os números antes de falar com o lead. Nesse
-- caso não houve retomada nenhuma: registrar o evento faria o vendedor parecer o
-- lead, e rearmar o relógio reiniciaria uma cadência por causa de um clique
-- interno. Em modo consulta a função só lê.
create or replace function public.funil_retomar(
  p_sessao   uuid,
  p_consulta boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_sessao public.funil_sessoes;
  v_prox   public.funil_etapas;
begin
  select * into v_sessao from public.funil_sessoes where id = p_sessao;
  if not found then
    return jsonb_build_object('ok', false);
  end if;

  if not p_consulta then
    insert into public.funil_eventos (sessao_id, tipo, etapa)
    values (v_sessao.id, 'sessao.retomada', v_sessao.etapa_concluida);
  end if;

  select * into v_prox from public.funil_etapas
   where ordem > v_sessao.ordem_concluida and ativo order by ordem limit 1;

  if not found and v_sessao.cta_clicado_em is null then
    select * into v_prox from public.funil_etapas where ordem = v_sessao.ordem_concluida and ativo;
  end if;

  if v_prox.etapa is not null and not p_consulta then
    insert into public.webhook_fila (sessao_id, etapa, tipo, agendado_para, ordem_referencia, chave_idempotencia)
    values (v_sessao.id, v_prox.etapa, 'etapa.timeout',
            now() + make_interval(secs => v_prox.timeout_segundos),
            v_sessao.ordem_concluida,
            v_sessao.id::text || ':timeout:' || v_prox.etapa)
    on conflict (chave_idempotencia) do update set
      status = 'pendente', agendado_para = excluded.agendado_para,
      ordem_referencia = excluded.ordem_referencia, tentativas = 0,
      request_id = null, http_status = null, resposta = null, erro = null,
      despachado_em = null, enviado_em = null
    where public.webhook_fila.status <> 'pendente';
  end if;

  return jsonb_build_object(
    'ok',              true,
    'sessao',          v_sessao.id,
    'integrador_id',   v_sessao.integrador_id,
    'projeto_id',      v_sessao.projeto_id,
    'etapa_concluida', v_sessao.etapa_concluida,
    'proxima',         v_prox.etapa,
    'dados',           v_sessao.dados
  );
end;
$$;

-- ── funil_salvar_avancado ───────────────────────────────────────────────────
-- configuracoes.html e sazonalidade.html vivem fora do funil, mas escrevem nas
-- mesmas colunas jsonb de `integradores`. Com o RLS fechado elas precisam de uma
-- porta própria — e ela é estreita de propósito: só três blocos, nomeados.
create or replace function public.funil_salvar_avancado(
  p_bloco       text,
  p_dados       jsonb,
  p_sessao      uuid default null,
  p_integrador_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_int_id uuid;
begin
  if p_bloco not in ('despesas', 'configs', 'sazonalidade', 'regime_tributario') then
    raise exception 'Bloco desconhecido: %', p_bloco using errcode = '22023';
  end if;

  select integrador_id into v_int_id from public.funil_sessoes where id = p_sessao;
  if v_int_id is null then
    select id into v_int_id from public.integradores where id = p_integrador_id;
  end if;
  if v_int_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'integrador não identificado');
  end if;

  if p_bloco = 'regime_tributario' then
    -- Única coluna de texto do conjunto: `#>> '{}'` tira o escalar de dentro do
    -- jsonb, senão gravaria com as aspas do JSON.
    update public.integradores
       set regime_tributario = nullif(p_dados #>> '{}', '')
     where id = v_int_id;
  else
    -- format() com %I sobre uma lista fechada: o nome já foi validado acima,
    -- então não há caminho de injeção, e evita repetir o mesmo UPDATE três vezes.
    execute format('update public.integradores set %I = $1 where id = $2', p_bloco)
      using p_dados, v_int_id;
  end if;

  return jsonb_build_object('ok', true, 'integrador_id', v_int_id);
end;
$$;

-- Leitura correspondente. As mesmas telas sincronizam do servidor ao abrir,
-- para quem volta em outro aparelho; com o RLS fechado elas não podem mais
-- fazer `select` direto na tabela.
create or replace function public.funil_ler_avancado(
  p_bloco         text,
  p_sessao        uuid default null,
  p_integrador_id uuid default null
)
returns jsonb
language plpgsql
security definer
stable
set search_path = public, pg_temp
as $$
declare
  v_int_id uuid;
  v_valor  jsonb;
begin
  if p_bloco not in ('despesas', 'configs', 'sazonalidade') then
    raise exception 'Bloco desconhecido: %', p_bloco using errcode = '22023';
  end if;

  select integrador_id into v_int_id from public.funil_sessoes where id = p_sessao;
  if v_int_id is null then
    select id into v_int_id from public.integradores where id = p_integrador_id;
  end if;
  if v_int_id is null then return null; end if;

  execute format('select %I from public.integradores where id = $1', p_bloco)
     into v_valor using v_int_id;

  return v_valor;
end;
$$;

-- ── Permissões ──────────────────────────────────────────────────────────────
-- O Postgres concede EXECUTE a PUBLIC por padrão em toda função criada. Revogar
-- e conceder nominalmente deixa explícito o que é superfície pública — e faz
-- qualquer função nova nascer fechada até alguém decidir o contrário.
revoke execute on function public.funil_config_publica()                             from public;
revoke execute on function public.funil_registrar_etapa(text, jsonb, uuid, jsonb, uuid, uuid) from public;
revoke execute on function public.funil_registrar_cta(uuid)                          from public;
revoke execute on function public.funil_retomar(uuid, boolean)                       from public;
revoke execute on function public.funil_salvar_avancado(text, jsonb, uuid, uuid)     from public;
revoke execute on function public.funil_ler_avancado(text, uuid, uuid)               from public;
revoke execute on function public.funil_normalizar_whatsapp(text)                    from public;

grant execute on function public.funil_config_publica()                             to anon, authenticated;
grant execute on function public.funil_registrar_etapa(text, jsonb, uuid, jsonb, uuid, uuid) to anon, authenticated;
grant execute on function public.funil_registrar_cta(uuid)                          to anon, authenticated;
grant execute on function public.funil_retomar(uuid, boolean)                       to anon, authenticated;
grant execute on function public.funil_salvar_avancado(text, jsonb, uuid, uuid)     to anon, authenticated;
grant execute on function public.funil_ler_avancado(text, uuid, uuid)               to anon, authenticated;
