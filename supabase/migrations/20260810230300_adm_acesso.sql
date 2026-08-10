-- Acesso do painel /adm.
--
-- O site é estático e a única chave que o navegador carrega é publicável, então
-- não existe "esconder a senha no JavaScript" — qualquer segredo que chegue ao
-- cliente já vazou. A saída é a senha nunca sair daqui: ela vive como hash
-- bcrypt em uma tabela sem GRANT nenhum, e o navegador só consegue perguntar
-- "esta senha confere?" através de uma função que devolve um token de sessão.
--
-- Consequência prática: mesmo quem tiver a chave publicável e chamar o
-- PostgREST na mão não consegue ler a configuração nem a base de leads.

create table if not exists public.adm_credencial (
  id            int primary key default 1 check (id = 1),
  senha_hash    text,
  atualizado_em timestamptz not null default now()
);

insert into public.adm_credencial (id) values (1) on conflict (id) do nothing;

create table if not exists public.adm_sessoes (
  token      uuid primary key default gen_random_uuid(),
  criado_em  timestamptz not null default now(),
  expira_em  timestamptz not null default now() + interval '8 hours',
  ultimo_uso timestamptz not null default now()
);

create table if not exists public.adm_tentativas (
  id        bigserial primary key,
  ip        text,
  sucesso   boolean not null,
  criado_em timestamptz not null default now()
);

create index if not exists idx_adm_tentativas_recentes on public.adm_tentativas(criado_em desc);

alter table public.adm_credencial enable row level security;
alter table public.adm_sessoes    enable row level security;
alter table public.adm_tentativas enable row level security;

revoke all on public.adm_credencial, public.adm_sessoes, public.adm_tentativas
  from anon, authenticated;

-- ── adm_definir_senha ───────────────────────────────────────────────────────
-- Chamada UMA vez, fora do navegador: pelo passo de deploy (com o secret
-- ADM_SENHA do GitHub) ou pelo SQL Editor do Supabase. Não tem GRANT para anon,
-- então não existe caminho para trocar a senha a partir do site.
create or replace function public.adm_definir_senha(p_senha text)
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if p_senha is null or length(p_senha) < 12 then
    raise exception 'A senha do painel precisa de ao menos 12 caracteres';
  end if;

  update public.adm_credencial
     set senha_hash = crypt(p_senha, gen_salt('bf', 10)),
         atualizado_em = now()
   where id = 1;

  -- Trocar a senha derruba quem já estava dentro. É o comportamento esperado
  -- quando a troca acontece porque a anterior vazou.
  delete from public.adm_sessoes;
end;
$$;

-- ── adm_ip ──────────────────────────────────────────────────────────────────
-- O PostgREST publica os cabeçalhos da requisição em um GUC. Sem isso não há
-- como distinguir uma tentativa de força bruta de um erro de digitação.
create or replace function public.adm_ip()
returns text
language sql
stable
set search_path = public, pg_temp
as $$
  select coalesce(
    split_part(nullif(current_setting('request.headers', true), '')::json->>'x-forwarded-for', ',', 1),
    'desconhecido'
  );
$$;

-- ── adm_login ───────────────────────────────────────────────────────────────
create or replace function public.adm_login(p_senha text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_hash  text;
  v_ip    text := public.adm_ip();
  v_falhas int;
  v_global int;
  v_token uuid;
begin
  -- Atraso fixo em toda tentativa. Serve para dois fins: iguala o tempo de
  -- resposta entre senha certa e errada (o bcrypt já ajuda, isto fecha o resto)
  -- e limita a taxa de tentativas por conexão a algo humano.
  perform pg_sleep(0.4);

  select count(*) into v_falhas from public.adm_tentativas
   where ip = v_ip and not sucesso and criado_em > now() - interval '15 minutes';

  select count(*) into v_global from public.adm_tentativas
   where not sucesso and criado_em > now() - interval '15 minutes';

  if v_falhas >= 10 or v_global >= 60 then
    insert into public.adm_tentativas (ip, sucesso) values (v_ip, false);
    return jsonb_build_object('ok', false, 'motivo', 'bloqueado',
      'mensagem', 'Muitas tentativas. Espere 15 minutos e tente de novo.');
  end if;

  select senha_hash into v_hash from public.adm_credencial where id = 1;

  if v_hash is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_senha',
      'mensagem', 'O painel ainda não tem senha definida. Rode adm_definir_senha uma vez.');
  end if;

  if crypt(coalesce(p_senha, ''), v_hash) <> v_hash then
    insert into public.adm_tentativas (ip, sucesso) values (v_ip, false);
    return jsonb_build_object('ok', false, 'motivo', 'senha',
      'mensagem', 'Senha incorreta.');
  end if;

  insert into public.adm_tentativas (ip, sucesso) values (v_ip, true);
  delete from public.adm_sessoes where expira_em < now();

  insert into public.adm_sessoes default values returning token into v_token;
  return jsonb_build_object('ok', true, 'token', v_token);
end;
$$;

create or replace function public.adm_logout(p_token uuid)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  delete from public.adm_sessoes where token = p_token;
$$;

-- ── adm_exigir ──────────────────────────────────────────────────────────────
-- Guarda de entrada de toda função do painel. Levanta exceção em vez de
-- devolver false: assim é impossível esquecer de checar o retorno em alguma
-- função nova e deixar uma porta aberta por descuido.
create or replace function public.adm_exigir(p_token uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.adm_sessoes set ultimo_uso = now()
   where token = p_token and expira_em > now();

  if not found then
    raise exception 'Sessão do painel inválida ou expirada' using errcode = '28000';
  end if;
end;
$$;

-- ── adm_config_ler ──────────────────────────────────────────────────────────
-- Devolve o segredo do HMAC de propósito: quem está no painel precisa dele para
-- configurar a verificação de assinatura do lado do n8n.
create or replace function public.adm_config_ler(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_cfg public.funil_config;
begin
  perform public.adm_exigir(p_token);
  select * into v_cfg from public.funil_config where id = 1;

  return jsonb_build_object(
    'cta_whatsapp',           v_cfg.cta_whatsapp,
    'site_url',               v_cfg.site_url,
    'webhook_url_eventos',    v_cfg.webhook_url_eventos,
    'webhook_segredo',        v_cfg.webhook_segredo,
    'webhook_max_tentativas', v_cfg.webhook_max_tentativas,
    'etapas', (
      select coalesce(jsonb_agg(to_jsonb(e) order by e.ordem), '[]'::jsonb)
        from public.funil_etapas e
    )
  );
end;
$$;

-- ── adm_config_salvar ───────────────────────────────────────────────────────
create or replace function public.adm_config_salvar(p_token uuid, p_config jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare e jsonb;
begin
  perform public.adm_exigir(p_token);

  update public.funil_config set
    cta_whatsapp           = nullif(trim(coalesce(p_config->>'cta_whatsapp','')), ''),
    site_url               = coalesce(nullif(trim(coalesce(p_config->>'site_url','')), ''), site_url),
    webhook_url_eventos    = nullif(trim(coalesce(p_config->>'webhook_url_eventos','')), ''),
    webhook_max_tentativas = greatest(1, least(10,
                               coalesce((p_config->>'webhook_max_tentativas')::int, webhook_max_tentativas))),
    atualizado_em          = now()
  where id = 1;

  -- Só os campos configuráveis são tocados. `etapa`, `ordem`, `rotulo` e `href`
  -- espelham AppCore.PASSOS e mudam com o código, não pelo painel — deixar o
  -- painel reordenar o funil quebraria o stepper sem aviso.
  for e in select * from jsonb_array_elements(coalesce(p_config->'etapas', '[]'::jsonb))
  loop
    update public.funil_etapas set
      timeout_segundos = greatest(60, coalesce((e->>'timeout_segundos')::int, timeout_segundos)),
      webhook_url      = nullif(trim(coalesce(e->>'webhook_url','')), ''),
      ativo            = coalesce((e->>'ativo')::boolean, ativo),
      atualizado_em    = now()
    where etapa = e->>'etapa';
  end loop;

  return public.adm_config_ler(p_token);
end;
$$;

create or replace function public.adm_rotacionar_segredo(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
begin
  perform public.adm_exigir(p_token);
  update public.funil_config
     set webhook_segredo = encode(gen_random_bytes(32), 'hex'), atualizado_em = now()
   where id = 1;
  return public.adm_config_ler(p_token);
end;
$$;

-- ── adm_leads ───────────────────────────────────────────────────────────────
-- `parou_em` é a pergunta que o painel existe para responder: não "até onde
-- chegou" mas "onde travou", que é a etapa seguinte à última concluída.
create or replace function public.adm_leads(p_token uuid, p_filtro jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_etapa  text := nullif(p_filtro->>'etapa','');
  v_busca  text := nullif(trim(coalesce(p_filtro->>'busca','')),'');
  v_de     timestamptz := coalesce((p_filtro->>'de')::timestamptz, now() - interval '90 days');
  v_ate    timestamptz := coalesce((p_filtro->>'ate')::timestamptz, now());
  v_limite int := least(500, greatest(1, coalesce((p_filtro->>'limite')::int, 100)));
  v_offset int := greatest(0, coalesce((p_filtro->>'offset')::int, 0));
begin
  perform public.adm_exigir(p_token);

  return jsonb_build_object(
    'total', (
      select count(*) from public.funil_sessoes s
       where s.criado_em between v_de and v_ate
         and (v_etapa is null or coalesce(s.etapa_concluida,'') = v_etapa)
         and (v_busca is null or concat_ws(' ', s.nome_contato, s.nome_empresa, s.email, s.whatsapp, s.cnpj) ilike '%'||v_busca||'%')
    ),
    'leads', (
      select coalesce(jsonb_agg(l order by l.atualizado_em desc), '[]'::jsonb) from (
        select
          s.id, s.nome_contato, s.nome_empresa, s.cnpj, s.email,
          s.whatsapp, s.whatsapp_e164,
          s.etapa_concluida, s.ordem_concluida,
          (select e.etapa from public.funil_etapas e
            where e.ordem > s.ordem_concluida order by e.ordem limit 1) as parou_em,
          s.concluido_em is not null as concluiu,
          s.cta_clicado_em is not null as cta_clicado,
          s.criado_em, s.atualizado_em,
          s.origem->>'utm_source'   as utm_source,
          s.origem->>'utm_campaign' as utm_campaign,
          (select o.valor_venda from public.projetos o where o.id = s.projeto_id) as valor_venda,
          (select o.lucro_mensal from public.orcamentos o where o.id = s.orcamento_id) as lucro_mensal
        from public.funil_sessoes s
        where s.criado_em between v_de and v_ate
          and (v_etapa is null or coalesce(s.etapa_concluida,'') = v_etapa)
          and (v_busca is null or concat_ws(' ', s.nome_contato, s.nome_empresa, s.email, s.whatsapp, s.cnpj) ilike '%'||v_busca||'%')
        order by s.atualizado_em desc
        limit v_limite offset v_offset
      ) l
    )
  );
end;
$$;

-- ── adm_metricas ────────────────────────────────────────────────────────────
create or replace function public.adm_metricas(p_token uuid, p_filtro jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_de  timestamptz := coalesce((p_filtro->>'de')::timestamptz, now() - interval '30 days');
  v_ate timestamptz := coalesce((p_filtro->>'ate')::timestamptz, now());
  v_total bigint;
begin
  perform public.adm_exigir(p_token);

  select count(*) into v_total from public.funil_sessoes
   where criado_em between v_de and v_ate;

  return jsonb_build_object(
    'total_sessoes', v_total,
    'concluiram',    (select count(*) from public.funil_sessoes
                       where criado_em between v_de and v_ate and concluido_em is not null),
    'clicaram_cta',  (select count(*) from public.funil_sessoes
                       where criado_em between v_de and v_ate and cta_clicado_em is not null),
    'etapas', (
      select coalesce(jsonb_agg(x order by x.ordem), '[]'::jsonb) from (
        select
          e.etapa, e.ordem, e.rotulo,
          -- Concluíram esta etapa (chegaram pelo menos até aqui).
          (select count(*) from public.funil_sessoes s
            where s.criado_em between v_de and v_ate and s.ordem_concluida >= e.ordem) as concluiram,
          -- Travaram exatamente aqui: concluíram a anterior e nunca esta.
          (select count(*) from public.funil_sessoes s
            where s.criado_em between v_de and v_ate and s.ordem_concluida = e.ordem - 1) as travaram,
          (select count(*) from public.webhook_fila w
            where w.tipo = 'etapa.timeout' and w.etapa = e.etapa and w.status = 'enviado'
              and w.criado_em between v_de and v_ate) as timeouts_enviados
        from public.funil_etapas e
      ) x
    ),
    'fila', (
      select coalesce(jsonb_object_agg(status, n), '{}'::jsonb)
        from (select status, count(*) n from public.webhook_fila
               where criado_em between v_de and v_ate group by status) q
    )
  );
end;
$$;

-- ── adm_fila / adm_reenviar / adm_testar_webhook ────────────────────────────
create or replace function public.adm_fila(p_token uuid, p_filtro jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_status text := nullif(p_filtro->>'status','');
  v_limite int  := least(300, greatest(1, coalesce((p_filtro->>'limite')::int, 60)));
begin
  perform public.adm_exigir(p_token);

  return (
    select coalesce(jsonb_agg(f order by f.criado_em desc), '[]'::jsonb) from (
      select w.id, w.tipo, w.etapa, w.status, w.url, w.tentativas, w.http_status,
             left(coalesce(w.erro,''), 300) as erro,
             w.agendado_para, w.criado_em, w.despachado_em, w.enviado_em,
             s.nome_contato, s.nome_empresa, s.whatsapp_e164
        from public.webhook_fila w
        left join public.funil_sessoes s on s.id = w.sessao_id
       where (v_status is null or w.status = v_status)
       order by w.criado_em desc
       limit v_limite
    ) f
  );
end;
$$;

create or replace function public.adm_reenviar(p_token uuid, p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.adm_exigir(p_token);

  update public.webhook_fila
     set status = 'pendente', agendado_para = now(), tentativas = 0,
         request_id = null, http_status = null, erro = null, resposta = null,
         despachado_em = null, enviado_em = null
   where id = p_id;

  return jsonb_build_object('ok', found);
end;
$$;

-- Enfileira um disparo de mentira para a URL informada, com corpo de exemplo e a
-- mesma assinatura dos disparos reais. É como o time de automação valida o
-- endpoint antes de existir um lead de verdade.
create or replace function public.adm_testar_webhook(p_token uuid, p_url text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare v_id uuid;
begin
  perform public.adm_exigir(p_token);

  if coalesce(trim(p_url), '') = '' then
    raise exception 'Informe a URL a testar';
  end if;

  insert into public.webhook_fila (tipo, url, payload, chave_idempotencia)
  values (
    'webhook.teste', trim(p_url),
    jsonb_build_object(
      'evento', 'webhook.teste',
      'etapa',  'custos',
      'etapa_rotulo', 'Custos',
      'ocorrido_em', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
      'lead', jsonb_build_object(
        'sessao', '00000000-0000-0000-0000-000000000000',
        'nome_contato', 'Maria Silva', 'nome_empresa', 'Solar Norte Energia',
        'cnpj', '00.000.000/0000-00', 'email', 'maria@exemplo.com.br',
        'whatsapp', '(11) 98765-4321', 'whatsapp_e164', '+5511987654321',
        'teste', true),
      'funil', jsonb_build_object(
        'etapa_concluida', 'projeto', 'ordem_concluida', 2, 'total_etapas', 4,
        'parou_em', 'custos', 'concluiu', false, 'cta_clicado', false,
        'minutos_parado', 63),
      'origem', jsonb_build_object('utm_source', 'teste'),
      'links', jsonb_build_object(
        'retomar',   rtrim((select site_url from public.funil_config where id = 1), '/') || '/custos?s=00000000-0000-0000-0000-000000000000',
        'resultado', rtrim((select site_url from public.funil_config where id = 1), '/') || '/?v=00000000-0000-0000-0000-000000000000',
        'relatorio', rtrim((select site_url from public.funil_config where id = 1), '/') || '/relatorio?v=00000000-0000-0000-0000-000000000000',
        'resultado_completo', false)
    ),
    'teste:' || gen_random_uuid()::text
  )
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

-- ── Permissões ──────────────────────────────────────────────────────────────
-- adm_definir_senha e adm_exigir NÃO recebem grant: a primeira é operação de
-- deploy, a segunda é uso interno das outras funções.
revoke execute on function public.adm_definir_senha(text)         from public;
revoke execute on function public.adm_exigir(uuid)                from public;
revoke execute on function public.adm_ip()                        from public;
revoke execute on function public.adm_login(text)                 from public;
revoke execute on function public.adm_logout(uuid)                from public;
revoke execute on function public.adm_config_ler(uuid)            from public;
revoke execute on function public.adm_config_salvar(uuid, jsonb)  from public;
revoke execute on function public.adm_rotacionar_segredo(uuid)    from public;
revoke execute on function public.adm_leads(uuid, jsonb)          from public;
revoke execute on function public.adm_metricas(uuid, jsonb)       from public;
revoke execute on function public.adm_fila(uuid, jsonb)           from public;
revoke execute on function public.adm_reenviar(uuid, uuid)        from public;
revoke execute on function public.adm_testar_webhook(uuid, text)  from public;

grant execute on function public.adm_login(text)                 to anon, authenticated;
grant execute on function public.adm_logout(uuid)                to anon, authenticated;
grant execute on function public.adm_config_ler(uuid)            to anon, authenticated;
grant execute on function public.adm_config_salvar(uuid, jsonb)  to anon, authenticated;
grant execute on function public.adm_rotacionar_segredo(uuid)    to anon, authenticated;
grant execute on function public.adm_leads(uuid, jsonb)          to anon, authenticated;
grant execute on function public.adm_metricas(uuid, jsonb)       to anon, authenticated;
grant execute on function public.adm_fila(uuid, jsonb)           to anon, authenticated;
grant execute on function public.adm_reenviar(uuid, uuid)        to anon, authenticated;
grant execute on function public.adm_testar_webhook(uuid, text)  to anon, authenticated;
