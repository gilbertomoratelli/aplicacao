# Auditor de Precificação — FAVO Educação

Aplicação web para integradoras de energia solar calcularem o preço mínimo de
venda de um projeto e enxergarem se o preço praticado hoje dá lucro ou prejuízo.

São páginas HTML estáticas, sem build. O banco é Supabase.

## Rodar localmente

Precisa de [Docker](https://www.docker.com/) rodando e do
[Supabase CLI](https://supabase.com/docs/guides/cli).

```bash
# 1. Sobe o banco local (Postgres + Auth + Studio) e aplica as migrations
supabase start

# 2. Serve os arquivos. Precisa ser por HTTP: abrir o .html com dois cliques
#    (file://) quebra o Supabase e o carregamento do shared.css.
python3 -m http.server 8765
```

Abra <http://127.0.0.1:8765/cadastro.html>.

| Serviço | Endereço |
|---|---|
| Aplicação | <http://127.0.0.1:8765> |
| API do Supabase | <http://127.0.0.1:54321> |
| Studio (ver e editar o banco) | <http://127.0.0.1:54323> |
| E-mails de teste | <http://127.0.0.1:54324> |

Não é preciso configurar nada: o `config.js` detecta que o host é local e aponta
para o Supabase da sua máquina. Em qualquer outro host ele usa produção.

### Comandos úteis

```bash
supabase stop        # derruba os containers (os dados ficam)
supabase db reset    # recria o banco do zero a partir de supabase/migrations/
supabase status      # endereços e chaves do ambiente local
```

## Estrutura

| Arquivo | Papel |
|---|---|
| `shared.css` | Fonte única dos tokens visuais e componentes. Sistema **Colmeia · iOS** |
| `app-core.js` | Helpers compartilhados: cliente do banco, stepper, máscaras, validação |
| `config.js` | Endereço e chave do banco. Escolhe local ou produção pelo host |
| `supabase/migrations/` | Schema versionado — é o que `supabase start` aplica |
| `design/` | Marca e os protótipos que originaram o sistema visual |

O fluxo de telas é derivado de `AppCore.PASSOS` (em `app-core.js`): para
adicionar, remover ou reordenar uma etapa, edite **só** aquela lista — o stepper
de todas as páginas vem dela.

## Publicação

A versão paralela do funil (`grupofavo.com/precificacao`) é publicada pelo
workflow `.github/workflows/deploy-precificacao.yml`, sempre por disparo manual
em Actions → *Run workflow*. Ele usa um projeto Supabase próprio, separado deste.
