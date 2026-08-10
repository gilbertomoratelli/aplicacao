# Referência completa do cálculo

Documento de conferência. Aqui está tudo que a ferramenta faz, na ordem em que faz, com as fórmulas literais, os nomes das variáveis e os pontos exatos do código. Serve para bater linha a linha com o que existe no sistema.

Fonte: `index.html` e `app-core.js`.

---

## 1. Inventário de parâmetros

### 1.1 Entradas do projeto

| Variável | Campo | Unidade | Origem |
|---|---|---|---|
| `kit` | Custo do KIT | R$ | `projeto.custo_kit` ou configuração |
| `ca` | Material adicional CA | R$ | configuração |
| `inst` | Instalação | R$ | configuração |
| `proj` | Projeto elétrico | R$ | configuração |
| `homol` | Homologação | R$ | configuração |
| `art` | ART do projeto | R$ | configuração |
| `custosExtras[]` | Custos adicionais criados pelo usuário | R$ | `custosExtras` |
| `ticket` | Preço de venda praticado | R$ | `projeto.valor_venda`, sazonalidade ou digitado |
| `qtd` | Projetos por mês | un | digitado |

### 1.2 Percentuais

| Variável | Campo | Unidade | Origem |
|---|---|---|---|
| `comissao` | Comissão de vendas | % | `despesas.comissao.valor` |
| `comissaoBase` | Base da comissão | `total` ou `servico` | `despesas.comissao.base` |
| `tributo` | Carga tributária | % | `despesas.tributo.valor` |
| `tributoBase` | Base do tributo | `total` ou `servico` | `despesas.tributo.base` |
| `outras` | Outras despesas variáveis | % | digitado |
| `despesasExtras[]` | Despesas variáveis nomeadas | % cada, com base própria | `despesas.extras` |
| `lucroAlvo` | Margem de lucro líquida alvo | % | `integrador.lucro_alvo` |

### 1.3 Despesa fixa

| Variável | Significado | Origem |
|---|---|---|
| `despFixa` | Despesa fixa mensal em R$ | `despesas.despFixa` |
| `despFixaPct` | Despesa fixa como % do faturamento | calculado da sazonalidade |

### 1.4 Drivers do projeto

| Variável | Origem |
|---|---|
| `kwp_sistema` | `projeto.kwp_sistema` |
| `quantidade_modulos` | `projeto.quantidade_modulos` |

### 1.5 Valores padrão

```
kit 12000, ca 800, inst 2500, proj 600, homol 400, art 0
ticket 22000, qtd 1
comissao 5, tributo 6, outras 1
despFixa 15000, lucroAlvo 12
comissaoBase "total", tributoBase "servico"
```

Referência: `index.html:493`

---

## 2. Precedência de carga

A ordem importa porque três fontes disputam os mesmos campos. Quem roda depois sobrescreve quem rodou antes. Sequência literal em `index.html:1335` até `1375`:

```
1.  load()                     aplica precSolar, ou os padrões se não houver
2.  carregarConfigs()          carrega configCustos e custosExtras
3.  carregarDespesas()         sobrescreve comissao, tributo, despFixa e as bases
4.  renderExtras()
5.  aplicarTodasConfigs()      sobrescreve kit, ca, inst, proj, homol, art
6.  projeto.custo_kit          sobrescreve kit, se existir
7.  qtd = 1                    só se precSolar.qtd não existir
8.  carregarSazonalidade()     define despFixaPct, e ticket se não houver valor_venda
9.  projeto.valor_venda        sobrescreve ticket, se existir
10. integrador.lucro_alvo      sobrescreve lucroAlvo, se existir
11. initDone = true, render()
```

Precedência final do `ticket`, do mais forte para o mais fraco:

```
projeto.valor_venda  >  ticket médio da sazonalidade  >  precSolar  >  padrão
```

Precedência final do `kit`:

```
projeto.custo_kit  >  configuração do campo kit  >  precSolar  >  padrão
```

Local contra banco: em `carregarConfigs` e `carregarDespesas`, se já existe dado local, o banco não é consultado. O local sempre vence. Não há mesclagem. Referência: `index.html:926` e `index.html:950`.

---

## 3. Regras de cálculo de custo por campo

Cada campo de custo pode ter uma configuração própria. Sem configuração, o valor é o que estiver digitado no campo.

### 3.1 Os quatro modos

```
modo = "fixo"    →  valor = taxa
modo = "modulo"  →  valor = taxa × quantidade_modulos
modo = "kwp"     →  valor = taxa × kwp_sistema
modo = "faixa"   →  ver 3.2
```

Referência: `calcValor()` em `index.html:1056` e `calcValorExtra()` em `index.html:1252`.

Diferença de comportamento entre os dois: `calcValor` devolve `null` quando não há configuração, e o valor digitado no campo é preservado. `calcValorExtra` devolve `0`.

### 3.2 Modo faixa

```
varVal  = (cfg.faixaVariavel === "modulos") ? quantidade_modulos : kwp_sistema
sorted  = faixas ordenadas por `ate` crescente, com null tratado como infinito
faixa   = primeira em que (ate === null) ou (varVal <= ate)
          se nenhuma casar, usa a última
taxa    = faixa.taxa ou 0

subModo = "fixo"    →  valor = taxa
subModo = "modulo"  →  valor = taxa × quantidade_modulos
subModo = "kwp"     →  valor = taxa × kwp_sistema
```

Referência: `calcValorFaixa()` em `index.html:1042`.

Ponto crítico: a faixa é aplicada **cheia**, não em degraus. Ao cair na faixa, a taxa dela vale para toda a quantidade. Consequência quantificada no item 9.4.

Padrão de `subModo` dentro de `calcValorFaixa` é `"kwp"`. Padrão na interface é `"modulo"`. Divergência registrada no item 9.6.

---

## 4. Passo 1: custo direto total

```
cdt = kit + ca + inst + proj + homol + art + totalExtras()

totalExtras() = soma de calcValorExtra(e) para cada e em custosExtras
```

Referência: `index.html:578` e `index.html:1262`.

Nada aqui depende do preço. É o único bloco que não é circular.

---

## 5. Passo 2: cenário de um preço qualquer

A função `cenario(tk, d)` monta o resultado completo para um preço `tk` informado. Ela é chamada duas vezes: uma com o ticket praticado, outra com o preço sugerido.

Referência: `index.html:553`.

```
baseServico = tk − kit

cBase = (comissaoBase === "total") ? tk : baseServico
tBase = (tributoBase  === "total") ? tk : baseServico

comissaoR = (comissao / 100) × cBase
tributoR  = (tributo  / 100) × tBase
outrasR   = (outras   / 100) × tk

para cada e em despesasExtras:
    base_e = (e.base === "servico") ? baseServico : tk
    v_e    = (e.valor / 100) × base_e
extrasR = soma de v_e

dvUnit = comissaoR + tributoR + outrasR + extrasR

faturamento      = tk × qtd
dvMes            = dvUnit × qtd
custoVariavelPct = (tk > 0) ? dvUnit / tk : 0

mcUnit = tk − cdt − dvUnit
mcPct  = (tk > 0) ? mcUnit / tk : 0
mcMes  = mcUnit × qtd

despFixaUnit = (despFixaPct > 0) ? tk × (despFixaPct / 100)
                                 : (qtd > 0 ? despFixa / qtd : 0)
despFixaMes  = (despFixaPct > 0) ? despFixaUnit × qtd : despFixa

lucroUnit = mcUnit − despFixaUnit
lucroMes  = mcMes  − despFixaMes
lucroPct  = (tk > 0) ? lucroUnit / tk : 0
```

Atenção nas duas linhas de despesa fixa. Elas têm dois comportamentos distintos conforme `despFixaPct` seja maior que zero ou não. É a origem do defeito 9.2.

---

## 6. Passo 3: preço sugerido

### 6.1 As quatro linhas

Referência: `index.html:580` até `588`.

```
cPctServ = (comissaoBase === "servico") ? comissao / 100 : 0
tPctServ = (tributoBase  === "servico") ? tributo  / 100 : 0
abat     = (cPctServ + tPctServ) × kit

baseVar  = comissao / 100 + tributo / 100 + outras / 100

fatAtual = ticket × qtd
dfPct    = (despFixaPct > 0) ? despFixaPct / 100
                             : (fatAtual > 0 ? despFixa / fatAtual : Infinity)

denom         = 1 − baseVar − dfPct − lucroAlvo / 100
precoSugerido = (denom > 0) ? (cdt − abat) / denom : Infinity
```

### 6.2 Derivação completa

A identidade que se quer resolver é:

```
P = cdt + DespesasVariaveis(P) + DespesaFixa(P) + Lucro(P)
```

Expandindo o termo de despesas variáveis. Uma despesa com base `total` incide sobre `P`. Uma despesa com base `servico` incide sobre `P − kit`, e isso se abre em duas parcelas:

```
p × (P − kit) = p × P − p × kit
```

Logo, tratando todas as despesas como se incidissem sobre `P` e descontando o excedente:

```
DespesasVariaveis(P) = baseVar × P − abat
onde abat = (cPctServ + tPctServ) × kit
```

Os outros dois termos:

```
DespesaFixa(P) = dfPct × P
Lucro(P)       = (lucroAlvo / 100) × P
```

Substituindo tudo:

```
P = cdt + baseVar × P − abat + dfPct × P + L × P
P − baseVar × P − dfPct × P − L × P = cdt − abat
P × (1 − baseVar − dfPct − L) = cdt − abat
```

Resultado:

```
                cdt − abat
P = ─────────────────────────────────
     1 − baseVar − dfPct − lucroAlvo/100
```

### 6.3 Leitura do denominador

O denominador é a fração do preço que sobra depois de reservar todos os percentuais. Se comissão, tributo e outras somam 12%, despesa fixa consome 17% e a margem alvo é 12%, então 41% do preço já tem destino e sobram 59% para pagar o custo direto. O preço é o custo dividido por 0,59.

### 6.4 Multiplicador implícito

```
P / cdt = (1 − abat / cdt) / denom
```

Quando não há despesa com base `servico`, `abat` é zero e o multiplicador vira exatamente `1 / denom`, constante para qualquer porte de projeto. Quando há, ele diminui proporcionalmente ao peso do kit dentro do custo.

---

## 7. Passo 4: ponto de equilíbrio

Referência: `index.html:592` até `595`.

```
peFat = (mcPct  > 0) ? despFixaMes / mcPct  : Infinity
peQtd = (mcUnit > 0) ? despFixaMes / mcUnit : Infinity
```

Os mesmos dois cálculos são repetidos usando o cenário do preço sugerido, gerando `peFatSug` e `peQtdSug`.

Na tela, `peQtd` é exibido com arredondamento para cima.

---

## 8. Passo 5: indicadores de markup

Referência: `index.html:680` até `683`.

```
mkAtual    = (ticket > 0) ? cdt / ticket : null
mkSug      = (precoSugerido finito e > 0) ? cdt / precoSugerido : null
multiAtual = (cdt > 0 e ticket > 0) ? ticket / cdt : null
multiSug   = (cdt > 0 e precoSugerido finito e > 0) ? precoSugerido / cdt : null
```

`mk` é o custo como percentual do preço. `multi` é o markup no sentido usual, quantas vezes o preço é maior que o custo.

---

## 9. Passo 6: linhas do resultado

Ordem literal das linhas, com as duas colunas. Referência: `index.html:629` até `641`.

| Linha | Por projeto | No mês |
|---|---|---|
| Receita (ticket) | `ticket` | `faturamento` |
| (−) Custo do KIT | `−kit` | `−kit × qtd` |
| (−) Custos de serviço | `−(cdt − kit)` | `−(cdt − kit) × qtd` |
| (−) Comissão de vendas | `−comissaoR` | `−comissaoR × qtd` |
| (−) Carga tributária | `−tributoR` | `−tributoR × qtd` |
| (−) Cada despesa extra | `−v_e` | `−v_e × qtd` |
| (−) Outras desp. variáveis | `−outrasR` | `−outrasR × qtd` |
| = Despesas variáveis | `−dvUnit` | `−dvMes` |
| = Margem de contribuição | `mcUnit` | `mcMes` |
| (−) Despesas fixas | `−despFixaUnit` | `−despFixaMes` |
| = Resultado | `lucroUnit` | `lucroMes` |

A linha de outras despesas variáveis só aparece quando `outras > 0`.

---

## 10. Sazonalidade

Referência: `index.html:1009`.

```
totalProjetos = soma de meses[m].projetos
totalValor    = soma de meses[m].valor

se totalProjetos = 0 e totalValor = 0, não aplica nada

ticketMedio = (totalProjetos > 0) ? totalValor / totalProjetos : 0
fatMedio    = totalValor / 12

despFixaPct = (fatMedio > 0) ? (despesas.despFixa / fatMedio) × 100 : 0

se ticketMedio > 0 e não houver projeto.valor_venda:
    ticket = ticketMedio
```

`fatMedio` divide sempre por 12, mesmo que menos de 12 meses estejam preenchidos. Registrado no item 11.7.

---

## 11. Regras de leitura de número

Todo texto digitado passa por `AppCore.parseNum`. Referência: `app-core.js:29`.

```
1. Se for número finito, devolve ele mesmo. Se for número não finito, devolve 0.
2. Se for null ou undefined, devolve 0.
3. Remove tudo que não seja dígito, vírgula, ponto ou hífen.
4. Se sobrou string vazia, devolve 0.
5. Se tem vírgula:
      remove todos os pontos, troca a vírgula por ponto decimal.
6. Se não tem vírgula mas tem ponto:
      mais de um ponto                              → todos são milhar, remove
      um ponto e o último grupo tem 3 dígitos       → é milhar, remove
      qualquer outro caso                           → o ponto é decimal
7. Se o resultado for NaN, devolve 0.
```

Casos de conferência:

| Entrada | Saída |
|---|---|
| `12.500,00` | 12500 |
| `1.234.567,89` | 1234567.89 |
| `12.5` | 12.5 |
| `12.55` | 12.55 |
| `1.500` | 1500 |
| `R$ 3,50` | 3.5 |

Cuidado conhecido: `1.500` sempre vira mil e quinhentos. Quem quiser digitar um vírgula cinco escrevendo `1.500` perde o valor.

---

## 12. O que é gravado

Payload da tabela `orcamentos`. Referência: `index.html:860`.

```
integrador_id, projeto_id
kit, ca, instalacao, projeto, homologacao, art
ticket, qtd_projetos
comissao_pct, comissao_base
tributo_pct, tributo_base
outras_pct
despesas_fixas, lucro_alvo_pct
custo_direto_total
faturamento_mensal
margem_contribuicao_pct
lucro_mensal
ponto_equilibrio_qtd
preco_sugerido
```

O que **não** é gravado e deveria ser, para reconstituir o cálculo depois: `despFixaPct`, as despesas variáveis extras com nome, base e percentual, os custos extras com a regra aplicada, e os drivers do projeto (kWp e módulos).

---

## 13. Casos degenerados

| Situação | O que acontece |
|---|---|
| `denom <= 0` | `precoSugerido = Infinity`, tela mostra mensagem de inválido |
| `fatAtual = 0` e `despFixaPct = 0` | `dfPct = Infinity`, `denom` negativo, mesmo efeito acima |
| `ticket = 0` | `mcPct`, `lucroPct` e `custoVariavelPct` devolvem 0 |
| `qtd = 0` e `despFixaPct = 0` | `despFixaUnit = 0` |
| `mcUnit <= 0` | ponto de equilíbrio em quantidade vira infinito |
| `mcPct <= 0` | ponto de equilíbrio em faturamento vira infinito |
| `cdt = 0` | markup não é calculado, devolve null |

---

## 14. Vetores de teste

Use estes casos para bater contra o sistema. Todos os números conferidos.

### 14.1 Vetor base

**Entradas**

```
kit 12000, ca 800, inst 2500, proj 600, homol 400, art 0
custosExtras vazio
ticket 22000, qtd 4
comissao 5 base total
tributo 6 base servico
outras 1
despesasExtras vazio
despFixa 15000, despFixaPct 0
lucroAlvo 12
```

**Saídas do preço sugerido**

| Variável | Valor |
|---|---|
| `cdt` | 16.300,00 |
| `cPctServ` | 0 |
| `tPctServ` | 0,06 |
| `abat` | 720,00 |
| `baseVar` | 0,12 |
| `fatAtual` | 88.000,00 |
| `dfPct` | 0,17045455 |
| `denom` | 0,58954545 |
| **`precoSugerido`** | **26.427,14** |

**Saídas do cenário no ticket praticado, 22.000**

| Variável | Valor |
|---|---|
| `baseServico` | 10.000,00 |
| `comissaoR` | 1.100,00 |
| `tributoR` | 600,00 |
| `outrasR` | 220,00 |
| `dvUnit` | 1.920,00 |
| `custoVariavelPct` | 8,7% |
| `faturamento` | 88.000,00 |
| `dvMes` | 7.680,00 |
| `mcUnit` | 3.780,00 |
| `mcPct` | 17,2% |
| `mcMes` | 15.120,00 |
| `despFixaUnit` | 3.750,00 |
| `despFixaMes` | 15.000,00 |
| `lucroUnit` | 30,00 |
| `lucroMes` | 120,00 |
| `lucroPct` | 0,1% |
| `peQtd` | 3,97, exibido como 4 |
| `peFat` | 87.301,59 |

**Indicadores de markup**

| Variável | Valor |
|---|---|
| `mkAtual` | 74,1% |
| `mkSug` | 61,7% |
| `multiAtual` | 1,35× |
| `multiSug` | 1,62× |

**Conferência da margem no preço sugerido**

Aplicando `dfPct` sobre o preço sugerido, que é o que a fórmula assume:

```
Receita                                    26.427,14
(−) cdt                                   −16.300,00
(−) comissão   5% × 26.427,14              −1.321,36
(−) tributo    6% × 14.427,14                −865,63
(−) outras     1% × 26.427,14                −264,27
(−) desp. fixa 17,045455% × 26.427,14      −4.504,63
= Resultado                                  3.171,25   →  12,00%
```

Fecha exatamente na margem alvo. É este fechamento que valida a fórmula.

### 14.2 Vetor com despesa variável extra

Igual ao vetor base, acrescentando `despesasExtras = [{ nome: "Marketing", valor: 3, base: "total" }]`.

| | Valor |
|---|---|
| `precoSugerido` que a ferramenta devolve | 26.427,14, inalterado |
| `precoSugerido` correto | 27.844,03 |
| Diferença | 1.416,89, ou 5,4% |
| Margem realmente entregue no preço da ferramenta | 9,0% em vez de 12% |

Este vetor isola o defeito 15.1.

### 14.3 Vetor de despesa fixa dominante

Igual ao vetor base, com `qtd = 1`.

| Variável | Valor |
|---|---|
| `fatAtual` | 22.000,00 |
| `dfPct` | 0,68181818 |
| `denom` | 0,07818182 |
| `precoSugerido` | 199.279,07 |

O número não está errado. Ele está dizendo que um único projeto por mês não sustenta 15 mil de estrutura com 12% de margem.

### 14.4 Vetor de meta impossível

Igual ao 14.3, com `lucroAlvo = 30`.

```
denom = 1 − 0,12 − 0,68181818 − 0,30 = −0,10181818
precoSugerido = Infinity
```

Tela deve bloquear com mensagem, não exibir número.

### 14.5 Vetor de faixa

```
faixaVariavel = "modulos"
subModo       = "modulo"
faixas = [ { ate: 20, taxa: 105 }, { ate: 50, taxa: 85 }, { ate: null, taxa: 70 } ]
```

| Módulos | Faixa escolhida | Cálculo | Valor |
|---|---|---|---|
| 20 | até 20 | 105 × 20 | 2.100,00 |
| 21 | 21 a 50 | 85 × 21 | 1.785,00 |
| 50 | 21 a 50 | 85 × 50 | 4.250,00 |
| 51 | acima de 50 | 70 × 51 | 3.570,00 |

Inversão em toda troca de faixa. De 20 para 21 módulos o custo cai 315. De 50 para 51 cai 680.

---

## 15. Defeitos encontrados

### 15.1 Despesas variáveis extras ficam fora do preço sugerido

`baseVar` soma apenas `comissao`, `tributo` e `outras`. Referência: `index.html:583`. O cenário, porém, desconta também `extrasR`. Referência: `index.html:560`.

Consequência: toda despesa variável nomeada cadastrada no onboarding é considerada no resultado mas não no preço. O preço sai subprecificado exatamente no percentual dessas despesas.

Correção: `baseVar` precisa somar todos os percentuais, e `abat` precisa somar `percentual × kit` de todo extra com base `servico`.

Quantificado no vetor 14.2.

### 15.2 Despesa fixa usa duas bases diferentes

O preço sugerido resolve com `dfPct`, um percentual do preço. O cenário calcula com `despFixa / qtd`, um valor absoluto por unidade, sempre que `despFixaPct` for zero.

```
index.html:586   dfPct        = despFixa / fatAtual
index.html:570   despFixaUnit = despFixa / qtd
```

No ticket praticado as duas coincidem por construção, já que `fatAtual = ticket × qtd`. No preço sugerido, não.

No vetor base: o cenário sugerido mostra despesa fixa de 3.750,00 e margem de 14,9%. A fórmula assumiu 4.504,63 e 12,0%. São 2,9 pontos de diferença, e a tela afirma uma margem que o preço não entrega.

Correção: escolher uma base e usar nas duas pontas.

### 15.3 O percentual de despesa fixa depende do preço praticado

Quando não há sazonalidade, `dfPct = despFixa / (ticket × qtd)`. O `ticket` usado é o praticado, que é justamente o que se está tentando calcular. Mudar o ticket praticado muda o preço sugerido, mesmo sem nenhum custo ter mudado.

Alternativa sem circularidade, usando valor absoluto por unidade:

```
P = (cdt + despFixa / qtd − abat) / (1 − baseVar − lucroAlvo / 100)
```

### 15.4 Faixa aplicada cheia gera inversão de preço

Detalhado no item 3.2 e quantificado no vetor 14.5. Acrescentar volume pode derrubar o custo e, por consequência, o preço.

Duas saídas: faixa em degraus, somando cada faixa até o limite dela, ou manter a faixa cheia e alertar na tela quando a inversão ocorrer. A escolha depende de como está o acordo com quem presta o serviço, porque a tabela do cálculo precisa ser igual à tabela do pagamento.

### 15.5 O campo de outras despesas variáveis fica escondido

`renderDespExtras` só exibe o campo `outras` quando existe pelo menos uma despesa extra, e zera o valor quando não existe. Referência: `index.html:982`.

Efeito: quem não cadastrou nenhuma despesa extra no onboarding não consegue informar outras despesas variáveis.

### 15.6 Divergência no padrão de subModo

`calcValorFaixa` assume `"kwp"` quando `subModo` está ausente. Referência: `index.html:1049`. A interface assume `"modulo"`. Referência: `index.html:1120`.

Configuração antiga ou incompleta pode calcular por kWp quando o usuário esperava por módulo.

### 15.7 Faturamento médio divide sempre por 12

`fatMedio = totalValor / 12`, mesmo com menos meses preenchidos. Referência: `index.html:1018`.

Efeito: com meia dúzia de meses preenchidos, o faturamento médio sai pela metade e `despFixaPct` sai inflado, o que empurra o preço sugerido para cima.

---

## 16. Forma generalizada

Retirando as particularidades do domínio solar, a fórmula é:

```
            CustoTotal + CustoFixoPorUnidade − Σ(pᵢ × deduçãoᵢ)
    P = ────────────────────────────────────────────────────────
                 1 − Σpᵢ − f − margemAlvo
```

Onde:

```
CustoTotal            soma de todos os custos em R$ do pedido
CustoFixoPorUnidade   overhead alocado em R$, zero se o overhead for percentual
pᵢ                    cada percentual que incide sobre o preço
deduçãoᵢ              parcela em R$ que não entra na base daquele percentual,
                      zero quando a base é o preço cheio
f                     overhead como percentual, zero se for alocado em R$
margemAlvo            margem líquida desejada, como fração
```

Regra de validação que precisa existir em qualquer implementação:

```
recompor(P) deve devolver margem igual a margemAlvo, com tolerância de arredondamento
```

Onde `recompor` refaz o resultado linha a linha a partir do preço calculado. Se esse teste passar para qualquer combinação de parâmetros, os defeitos 15.1, 15.2 e 15.3 não conseguem existir.
