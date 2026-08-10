-- Fecha o acesso direto do papel anônimo às tabelas de negócio.
--
-- O schema inicial liberou `for all to anon using (true)` nas três tabelas, com
-- a ressalva escrita no próprio arquivo de que aquilo reproduzia produção e não
-- era desenho de segurança. Na prática significava que qualquer visitante, com a
-- chave publicável que vai no JavaScript servido, podia baixar, alterar e APAGAR
-- a base inteira de leads. Esta migration encerra isso.
--
-- O que muda para quem escreve: nada é perdido. Todo caminho de escrita do funil
-- já passa pelas funções `security definer` (funil_registrar_etapa,
-- funil_salvar_avancado, funil_ler_avancado), que rodam como dono e por isso
-- atravessam o RLS. É por isso que esta migration vem por último: as telas já
-- foram migradas e validadas com o acesso antigo ainda aberto.

-- ── anon: sem acesso direto a nada ──────────────────────────────────────────
-- Duas camadas independentes precisam ser fechadas. Revogar o GRANT já faz o
-- PostgREST recusar antes de chegar ao RLS; derrubar a policy garante que um
-- GRANT concedido por engano no futuro não reabra tudo de uma vez.
do $$
declare t text;
begin
  foreach t in array array['integradores','projetos','orcamentos'] loop
    execute format('revoke all on public.%I from anon', t);
    execute format('drop policy if exists %I on public.%I', 'acesso_anon_'||t, t);
  end loop;
end $$;

-- ── authenticated: leitura, ainda sem amarração por usuário ─────────────────
-- historico.html e login.html continuam funcionando: elas já exigem sessão do
-- Supabase Auth. Isto tira a base de leads do acesso público, que é o problema
-- urgente, mas NÃO resolve o segundo: qualquer pessoa logada ainda vê tudo.
--
-- Amarrar `auth.uid()` a um integrador exige uma decisão de produto que não
-- existe hoje (quem pode ver o quê, e como um lead vira usuário), então fica
-- registrado como pendência explícita em vez de ser improvisado aqui.
do $$
declare t text;
begin
  foreach t in array array['integradores','projetos','orcamentos'] loop
    execute format('revoke all on public.%I from authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', 'leitura_autenticada_'||t, t);
    execute format(
      'create policy %I on public.%I for select to authenticated using (true)',
      'leitura_autenticada_'||t, t);
  end loop;
end $$;

comment on table public.integradores is
  'Acesso direto fechado para anon (ver 20260810230400_fechar_rls.sql). Escrita só pelas funções funil_*.';
