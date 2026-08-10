-- O cadastro captava só dados da empresa; faltava quem está preenchendo.
-- O funil é conversa com uma pessoa, e o time comercial precisa saber com
-- quem falar quando pegar o lead.
alter table public.integradores
  add column if not exists nome_contato text;
