# Precificação no sistema: o problema e a proposta

## Como funciona hoje

A gente definiu um markup padrão de 1,95 e aplica ele em todos os itens. O Alexandre sobe a planilha já com esse número embutido, então o que entra no sistema é preço de venda, não custo.

Dentro desse 1,95 está tudo junto e tudo em média: comissão, carga tributária, despesa fixa, folha, instalação, ART, homologação.

O problema é que essas coisas não se comportam do mesmo jeito quando o pedido muda de tamanho.

## Por que isso distorce

Pensa em três tipos de custo que hoje estão dentro do mesmo multiplicador:

**A ART é um valor fixo por projeto.** Custa o mesmo num pedido de 10 mil e num de 100 mil. Quando a gente joga ela dentro de um percentual, o pedido pequeno paga de menos e o grande paga de mais.

**A instalação anda ao contrário do tamanho.** Num pedido pequeno a gente paga 105 por módulo. Numa usina paga 70. É 35 reais de diferença por módulo, e a média de 8% ignora isso completamente.

**O equipamento também fica mais barato na escala.** Quanto maior a compra, menor o custo por módulo.

Ou seja, três forças puxando na mesma direção e o multiplicador único não enxerga nenhuma delas.

## O tamanho do estrago, com número

Números abaixo são hipotéticos, servem só para mostrar o mecanismo. Os reais entram na primeira fase do projeto.

Considerando comissão 6%, carga tributária 12%, despesa fixa 10% e margem alvo de 12%:

| | Residencial, 10 módulos | Usina, 200 módulos |
|---|---|---|
| Equipamento | 12.000 | 190.000 |
| Instalação | 1.050 | 14.000 |
| ART | 500 | 500 |
| Homologação | 400 | 400 |
| Deslocamento | 600 | 1.200 |
| **Custo total do pedido** | **14.550** | **206.100** |
| **Preço que o sistema deveria dar** | **24.250** | **343.500** |
| Preço que a gente pratica hoje | 23.400 | 370.500 |
| **Margem que o preço de hoje entrega** | **9,8%** | **16,4%** |

O residencial sai abaixo da meta de 12%. A usina sai 27 mil reais mais cara do que precisava ser.

Colocando de outro jeito: o markup que produziria o preço certo é **2,02 no residencial e 1,81 na usina**. O 1,95 fica no meio dos dois. Ele encarece a usina e barateia o residencial, exatamente ao contrário do que deveria.

## A ideia central

O 1,95 nunca foi o problema.

Se a gente montar o custo direito e aplicar os percentuais, o multiplicador é sempre o mesmo, 1,667 sobre o custo total, tanto no residencial quanto na usina. O que estava errado é que o 1,95 multiplica só o custo do equipamento e tenta, dentro do próprio número, cobrir custos que não têm nada a ver com o equipamento.

**A proposta é tirar esses custos de dentro do multiplicador e colocar no custo, que é onde eles conseguem escalar do jeito certo.**

Na prática:

1. O Alexandre passa a subir os itens a preço de custo.
2. A gente cadastra as tabelas de custo de instalação, ART, homologação e deslocamento, cada uma com a sua própria regra.
3. A gente cadastra os percentuais: comissão, carga tributária, despesa fixa e margem alvo.
4. Quando o representante monta o kit, o sistema calcula o preço de venda na hora.

## O que a gente ganha além do preço

O preço melhor é a parte óbvia. Tem três coisas que vêm junto e que valem mais:

**Pagamento de instalador sai do sistema.** Se o custo de instalação está setado por pedido, no fim do mês a gente filtra o que foi instalado e o relatório sai pronto, com a memória de cálculo. Hoje isso é uma pessoa dedicada em tempo integral e uma semana de conferência a cada quinzena.

**Margem real por pedido.** Dá para ver na ponta do lápis qual venda deu lucro e qual deu prejuízo, porque o custo de cada pedido fica registrado individualmente e não mais numa média.

**Cálculo de comissão fica mais simples**, porque passa a existir um valor de custo confiável dentro de cada pedido.

## O que este projeto não é

Não é um ERP e não é conciliação bancária. É rastreabilidade de custo e preço dentro do pedido. Despesa fixa entra como percentual configurado, não como lançamento contábil.
