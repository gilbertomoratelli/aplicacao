# Como o cálculo funciona

## A lógica em uma frase

Em vez de multiplicar o custo do equipamento por um número, a gente soma o custo real do pedido inteiro e divide pelo que sobra do preço depois de pagar todos os percentuais.

## Por que não dá para simplesmente somar tudo

Essa é a parte que confunde, então vale explicar.

Comissão é percentual do preço. Carga tributária é percentual do preço. Despesa fixa é percentual do preço. Margem também.

Só que o preço é justamente o que a gente está tentando descobrir. Um depende do outro.

A saída é olhar pelo avesso. Se comissão, tributo e despesa fixa somam 28%, e a gente quer 12% de margem, então 40% do preço já tem dono. Sobra 60% para pagar o custo.

Logo, se sobram 60% para o custo, o preço é o custo dividido por 0,60.

```
Preço = Custo total do pedido / (100% menos a soma de todos os percentuais)
```

Com custo de 14.550 e 60% sobrando:

```
14.550 / 0,60 = 24.250
```

Conferindo o resultado:

| | |
|---|---|
| Preço | 24.250 |
| Menos custo total | 14.550 |
| Menos comissão, 6% | 1.455 |
| Menos tributo, 12% | 2.910 |
| Menos despesa fixa, 10% | 2.425 |
| **Sobra** | **2.910, que é 12% do preço** |

Bate com a margem alvo. É esse fechamento que garante que o número está certo.

## Como cada custo é montado

Todo custo do pedido tem uma regra de como ele é calculado. São três formatos:

**Valor fixo.** ART, homologação. É sempre o mesmo valor, não importa o tamanho do pedido.

**Valor por unidade.** Multiplica uma taxa por alguma coisa do projeto, número de módulos ou potência em kWp. Serve para instalação e para qualquer coisa que acompanhe o tamanho.

**Tabela por faixa.** É o formato da instalação. Até 20 módulos vale uma taxa, de 21 a 50 vale outra, acima de 50 vale outra. E essa tabela pode ainda variar por tipo de estrutura, porque instalar em solo custa diferente de instalar em telhado.

Com esses três formatos a gente cobre tudo que existe hoje, e qualquer custo novo que aparecer amanhã entra em um deles.

## Um cuidado importante na tabela de faixas

Se a tabela funcionar como "caiu na faixa, a taxa vale para todos os módulos", acontece o seguinte:

| Módulos | Conta | Custo de instalação |
|---|---|---|
| 50 | 50 x 85 | 4.250 |
| 51 | 51 x 70 | 3.570 |

Um módulo a mais derruba o custo em 680 reais e o preço em 1.133 reais. O pedido de 51 módulos sai mais barato que o de 50. O comercial descobre isso em uma semana.

Tem duas saídas e é uma decisão de negócio, não de sistema:

**Primeira.** A tabela vira escalonada de verdade, os primeiros 20 módulos a 105, os próximos 30 a 85, o resto a 70. Aí nunca inverte. Mas isso só vale se a gente renegociar a tabela com os instaladores no mesmo formato.

**Segunda.** A tabela do sistema fica igual à tabela contratual dos instaladores, mesmo que ela inverta, e o sistema avisa na tela toda vez que a inversão acontecer.

A minha recomendação é a segunda, pelo menos no começo. Motivo: se a tabela do sistema for diferente da que a gente paga de verdade, o relatório de pagamento de instalador não fecha, e esse relatório é metade do valor do projeto.

## Por que o preço é do pedido e não do item

A ART é por projeto. Não existe jeito honesto de dividir uma ART entre um inversor e um cabo. O mesmo vale para deslocamento.

Então o custo só fecha quando o pedido está montado.

Mas o representante precisa ver preço enquanto monta o kit, e isso continua funcionando. A conta se separa em duas partes:

- **Tabela de referência por item.** É o custo do item dividido pelos mesmos 0,60. Fica sempre coerente e se atualiza sozinha quando a gente mexe em tributo ou margem.
- **Acréscimo do pedido.** ART, homologação, instalação e deslocamento entram quando o kit está fechado.

Na hora de mostrar o preço unitário de cada linha, o sistema distribui esse acréscimo proporcionalmente ao custo de cada item. O total bate exato e o representante continua vendo a tela do jeito que sempre viu.

## Casos que o sistema precisa avisar

**Meta impossível.** Se comissão, tributo, despesa fixa e margem somarem 100% ou mais, não existe preço que resolva. O sistema bloqueia e explica o motivo, em vez de mostrar um número maluco.

**Pedido abaixo do piso.** Pedido muito pequeno pode gerar um preço que parece absurdo por causa da ART e do deslocamento fixos. O número não está errado, ele está mostrando que aquele pedido é inviável. O sistema mostra o alerta em vez de esconder.

**Inversão de preço.** Todo caso em que acrescentar volume derruba o preço.

**Desconto que come a margem.** Quando o desconto do representante puxa a margem para abaixo do mínimo.
