# Plano de Correção — 2ª Rodada (Achados "Alto")

Continuação do [PLANO_CORRECAO.md](PLANO_CORRECAO.md), que cobriu os Críticos + A-1.
Este plano cobre os **12 Altos restantes (A-2 … A-13)**. Médios e Baixos ficam para depois.

## Princípio (mantido)

A fundação [app-core.js](app-core.js) já existe. Vários Altos são resolvidos **aplicando
helpers que já criamos** — nada novo a inventar:
- `AppCore.escapeHtml` → resolve A-5 (ainda não aplicado em nenhuma página; confirmado por grep).
- `AppCore.parseNum` → suporta A-2 quando os campos viram `type="text"`.

Mudança mínima e cirúrgica. Sem refatorar o que não é bug. SOLID/DRY/clean onde couber.

---

## Agrupamento por padrão (ordem de execução recomendada)

### Grupo 1 — Higienização de saída (A-5) · maior alcance, aplicar primeiro
**A-5 — Injeção/quebra de HTML via innerHTML com dados do usuário.**
Pontos confirmados por grep: `historico.html` (4×), `configuracoes.html` (4×),
`despesas.html` (2×), `indicadores.html` (4×).
- **Ação:** em cada interpolação de dado vindo do usuário/banco dentro de `innerHTML`
  (nome de empresa, projeto, label de custo/extra, e o `value="${...}"` de inputs de label),
  envolver com `AppCore.escapeHtml(...)`. Para o `value="..."` de input editável
  (configuracoes:418), escapar é obrigatório (aspas quebram o atributo).
- **Cuidado:** NÃO escapar valores numéricos já formatados nem markup estrutural próprio —
  só o texto livre. Não trocar innerHTML por textContent onde há markup intencional junto.
- **Por que primeiro:** um cliente com aspas ou `&` no nome quebra a tela na demo; é o Alto
  de maior probabilidade visual.

### Grupo 2 — Entrada numérica pt-BR que ainda escapa (A-2)
**A-2 — `type="number"` rejeita vírgula → vira 0 silenciosamente.**
Confirmado: `despesas.html:145` (comissao), `:157` (tributo), `:290` (extra-pct).
- **Ação:** trocar `type="number" step="0.1"` por `type="text" inputmode="decimal"` nesses
  campos. O parse já usa `AppCore.parseNum` (feito na 1ª rodada), então passa a aceitar
  "1,5" corretamente. Ajustar validação `:invalid`/`step` que dependa de number.
- **Verificar irmãos:** `configuracoes.html` usa `type="number"` em cfgTaxa/faixas — decidir
  caso a caso (a 1ª rodada considerou esses aceitáveis porque o browser normaliza; só migrar
  se a demo digitar vírgula neles). Documentar a decisão.

### Grupo 3 — Semântica de valor 0 vs. ausente (A-3, A-4)
**A-3 — alerta de lucro não dispara quando lucro_alvo está ausente (default 12 mascara).**
`indicadores.html:193,303`.
- **Ação:** basear o alerta em `integrador?.lucro_alvo == null` (ausência real), não no valor
  já com default aplicado. Separar "valor para exibir" (com default 12) de "está configurado?".

**A-4 — comissão/tributo de 0% exibidos como "Não informada".**
`indicadores.html:236-263`.
- **Ação:** trocar testes truthy (`x ? … : 'Não informada'`) por `x != null && x !== ''`.
- **Agrupados** porque são o mesmo defeito conceitual (falsy 0 tratado como vazio) na mesma
  página — um agente resolve os dois juntos.

### Grupo 4 — Integridade de dados / precedência (A-6, A-9, A-11, A-12, A-13)
**A-6 — custo_kit aceita 0/negativo; qtd_modulos valida float mas salva int.** `projeto.html:196,217`.
- **Ação:** `check: v => AppCore.parseNum(v) > 0`; unificar parse de validação e persistência
  (validar com o mesmo `parseInt`/`parseNum` que grava, para "2.5" não passar e virar 2).

**A-9 — comissaoBase/tributoBase duplicados entre precSolar e despesas (index).** `index.html:510-511 vs 910-914`.
- **Ação:** eleger UMA fonte de verdade. Recomendação: `despesas` (vem do onboarding) é a
  origem; `precSolar` não deve persistir a base — deriva de `despesas` no load. Remover a
  gravação duplicada, não adicionar sincronização.

**A-11 — fetch remoto sobrescreve campo que o usuário está editando.** `despesas.html:217-229`, `sazonalidade.html`.
- **Ação:** marcar campos "tocados" (flag em `input`/`focus`) e, ao aplicar dados remotos,
  pular os que o usuário já editou. Mínimo: um `Set` de ids tocados.

**A-12 — trocar de empresa não limpa dados financeiros da anterior.** `despesas.html:259-262`.
- **Ação:** em `trocarEmpresa()`, além de remover `integrador`, remover
  `despesas`, `configCustos`, `custosExtras`, `sazonalidade`, `projeto`, `precSolar`.
  Centralizar num `AppCore.clearOnboardingState()`? Só se usado em >1 lugar — senão inline
  (evitar abstração especulativa). Verificar se "trocar empresa"/"resetar" existe em outra página.

**A-13 — addFaixa usa último inserido, não o maior; faixas sobrepostas sem validação.** `configuracoes.html:576-585`.
- **Ação:** `Math.max(...nonNull.map(f=>f.ate))` para o próximo limite; validar monotonicidade
  ao aplicar e alertar (reusar `showToast`) se houver sobreposição/gap.

### Grupo 5 — Mensagens de estado (A-7, A-8)
**A-7 — botão "Continuar" perde `?onboarding=1` e quebra o stepper.** `configuracoes.html:207`.
- **Ação:** garantir o param no link de onboarding, OU derivar `isOnboarding` também da
  ausência de `projeto` no estado. Escolher uma; não as duas (evitar lógica redundante).

**A-8 — precoSugerido some quando faturamento atual é 0; mensagem ambígua.** `index.html:562`.
- **Ação:** separar a condição — "faturamento zero" e "meta impossível (denom≤0)" são causas
  distintas e devem ter mensagens distintas. O preço sugerido não deve depender de `fatAtual>0`.

---

## Coordenação do time (mesma estrutura que funcionou)

Sem Fase 1 nova — a fundação já existe. Fanout direto por arquivo (sem colisão):

- **Agente A** → Grupo 1 (A-5) em historico + indicadores.
- **Agente B** → Grupo 1 (A-5) em configuracoes + despesas · Grupo 2 (A-2) em despesas.
- **Agente C** → Grupo 3 (A-3, A-4) em indicadores.
- **Agente D** → A-6 em projeto · A-11/A-12 em despesas+sazonalidade · A-7 em configuracoes.
- **Agente E** → A-8, A-9 em index · A-13 em configuracoes.

> Nota de colisão: `configuracoes.html` é tocado por B (A-5, A-2-irmãos), D (A-7) e E (A-13);
> `despesas.html` por B e D. Para evitar edições concorrentes no mesmo arquivo, **reagrupar por
> arquivo** na hora de despachar (um agente por arquivo-alvo) em vez de por grupo temático.
> Regra prática: **um arquivo = um agente**. Reparto final sugerido:
> - historico.html → Ag.1 (A-5)
> - indicadores.html → Ag.2 (A-5, A-3, A-4)
> - despesas.html → Ag.3 (A-5, A-2, A-11, A-12)
> - configuracoes.html → Ag.4 (A-5, A-7, A-13)
> - index.html → Ag.5 (A-8, A-9)
> - sazonalidade.html → Ag.6 (A-11) [ou junto com despesas se leve]
> - projeto.html → Ag.7 (A-6)

- **Fase de revisão:** um Revisor confirma sintaxe (`node --check`), que `escapeHtml` cobre
  todos os pontos de innerHTML de usuário, que nenhuma fonte-de-verdade dupla sobrou (A-9),
  e roda a mesma bateria de smoke checks da 1ª rodada.

## Verificação de saída (evidência)
- `node --check` em todas as páginas.
- grep: nenhum `innerHTML` com `${` de dado de usuário sem `escapeHtml`.
- grep: nenhum `type="number"` remanescente nos campos monetários migrados.
- Teste manual do fluxo: nome de empresa com aspas/`&`; comissão "1,5"; trocar empresa e
  confirmar que dados antigos sumiram; faixa fora de ordem alertando.

## Fora do escopo deste plano
Todos os Médios (M-1..M-12), Baixos (B-1..B-8) e acessibilidade (B-1). Já documentados no
relatório de auditoria; entram numa 3ª rodada se desejado.
