# Plano de Correção — Escopo Crítico

Auditoria consolidou 48 achados. Este plano executa **tudo que é realmente crítico**:
os 9 Críticos (C-1..C-9) + A-1 (parse de milhar pt-BR, o bug financeiro de topo).
Altos/Médios/Baixos restantes ficam documentados para uma segunda rodada.

## Princípio central (DRY / anti-overengineering)

A maioria dos Críticos são instâncias de 4 padrões sistêmicos. Em vez de 10 patches
isolados, criamos **um único módulo compartilhado** e o aplicamos. Nada de framework,
build step ou abstração especulativa — só as funções que os bugs exigem.

### `app-core.js` (novo, na raiz) — fundação compartilhada

Exporta no escopo global (sem módulos ES, pois são HTMLs estáticos abertos via file/http):

- `AppCore.safeParse(key, fallback)` — resolve **Padrão 3** (JSON.parse sem try/catch → tela branca).
- `AppCore.parseNum(str)` — resolve **A-1 / Padrão 4**. Remove separador de milhar e troca
  vírgula decimal: `"12.500,00" → 12500`. Fonte única de parse numérico do app.
- `AppCore.escapeHtml(str)` — resolve Padrão 5 (fora do escopo crítico, mas o helper fica
  disponível; aplicação de escape entra na 2ª rodada).
- `AppCore.dbTry(promise)` — resolve **Padrão 2** (fetch sem try/catch). Envolve qualquer
  `await db…` e retorna sempre `{ data, error }`, nunca rejeita. Init/navegação nunca travam.
- `AppCore.getClient()` — resolve **C-1 / Padrão 1**. Retorna o client Supabase se o SDK
  carregou; senão retorna `null` e o app segue em modo somente-localStorage. A página nunca morre.
- `AppCore.uuid()` — id client-side (`crypto.randomUUID` com fallback) para C-2.

O `<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2">` continua, mas agora
com `onerror` + guarda: se falhar, `getClient()` devolve `null` em vez de `ReferenceError`.
> Nota de produção: para eliminar 100% a dependência externa, baixar o `supabase-js@2.x.y`
> oficial e servi-lo localmente (`<script src="vendor/supabase.js">`). É um passo de deploy,
> não de código.

## Correções por página (aplicando a fundação)

| ID   | Página(s)            | Correção |
|------|----------------------|----------|
| C-1  | todas                | SDK via `getClient()`; degrada para localStorage se CDN cair. |
| C-2  | cadastro, projeto    | Gravar localStorage com `uuid()` **antes** do await; DB vira sync opcional via `dbTry`. |
| C-3  | despesas, sazonalidade | try/catch/finally: reabilitar botão e navegar no `finally`. |
| C-4  | index                | Flag `initDone`: callbacks async só chamam `render()/save()` após load inicial; precedência única de escrita nos inputs. |
| C-5  | projeto              | Incluir `valor_venda` no payload do DB (além do localStorage). |
| C-6  | index                | Despesa fixa: mesma base (percentual do ticket) no cálculo por-projeto e no mês. |
| C-7  | configuracoes        | `dbTry` no carregarConfigs; em erro mantém localStorage e renderiza. |
| C-8  | configuracoes        | Toast só após sucesso real; diferenciar "salvo localmente" de "sincronizado". |
| C-9  | indicadores          | Ler configCustos com fallback ao DB (mesmo padrão do index), desaninhando `.campos`. |
| A-1  | despesas, projeto, sazonalidade, index, configuracoes | Trocar todo parse numérico por `AppCore.parseNum`. |

## Coordenação do time

- **Fase 1 — Arquiteto** cria `app-core.js` (todos dependem). Síncrono.
- **Fase 2 — Implementadores em paralelo** (worktrees isoladas) aplicam a fundação + correções
  nas suas páginas. Contrato de `AppCore` é fixo e publicado pelo arquiteto.
- **Fase 3 — Revisor** integra, checa DRY (nenhum helper reimplementado inline), contratos
  entre páginas (configCustos aninhado, valor_venda) e roda uma verificação de fumaça.

## Fora do escopo agora (2ª rodada)
Todos os Altos (exceto A-1), Médios e Baixos — incluindo escape HTML aplicado (A-5),
validações de faixa (A-13), acessibilidade (B-1). Documentados no relatório de auditoria.
