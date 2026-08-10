# Plano de implantação e o que precisa ser definido

## Fase 0: relatório de sombra

Não muda nada na operação. Ninguém percebe.

A gente cadastra os parâmetros reais e roda o cálculo em cima dos últimos 12 meses de pedidos já fechados. O resultado é um comparativo: preço praticado, preço que o motor teria dado, e margem que cada pedido entregou de verdade, separado por porte.

Duas a três semanas.

Faço questão dessa fase por três motivos:

1. **Valida as tabelas de custo antes de alguém depender delas.** Se a tabela de instalação estiver errada, é aqui que aparece, e não em produção.
2. **Dá o argumento numérico para a conversa com o comercial.** Ninguém discute com a lista dos pedidos que deram prejuízo.
3. **Evita o padrão que a gente já viveu.** Ferramenta que sai, roda um mês e morre. Aqui o resultado da fase 0 é o que compra a fase 1.

## Fase 1: catálogo a custo e cálculo no pedido

Compras passa a subir custo. A tabela de preço vira número derivado. O representante monta o kit e vê o preço calculado na hora. A conta de cada pedido fica congelada. Desconto fora da banda cai no fluxo de liberação que já existe.

## Fase 2: relatório de pagamento de instalador

Sai da conta congelada de cada pedido. É o retorno operacional mais rápido e provavelmente o que garante o apoio interno para o resto.

## Fase 3: previsto contra realizado

Registro do custo real ao lado do previsto, margem real por pedido, e a ligação com a parte financeira de rastreabilidade de recebimento.

## O que preciso do Gilberto para começar

São sete pontos, e a maior parte já saiu na conversa. Sem os dois primeiros eu não modelo nada.

**1. A tabela de instalação como ela é hoje.** Por faixa e por tipo de estrutura, do jeito que está no acordo com os instaladores. Este é o insumo número um. É ele que define se a tabela inverte ou não, e é ele que faz o relatório de pagamento bater.

**2. Instalação é sempre custo interno, ou em algum caso ela é vendida destacada?** Define se o sistema precisa tirar ela da conta do kit em alguns pedidos.

**3. Carga tributária é uma alíquota só, ou muda entre equipamento e serviço?** Se a gente fatura separado, são duas, e a diferença mexe na margem.

**4. Despesa fixa como percentual foi o pedido, e é assim que vou fazer.** Só quero medir no relatório de sombra a alternativa de um valor fixo por pedido. Motivo: o custo de retaguarda por pedido é praticamente o mesmo independente do tamanho, então ele reproduz em miniatura a mesma distorção da ART. Não trava nada, é só instrumentação.

**5. Comissão de representante e coordenador é percentual fixo ou tem régua por faixa de valor?** Se tiver régua, o cálculo precisa de um passo a mais. Resolve igual, mas muda a implementação.

**6. Margem alvo é uma só, ou muda por linha?** Residencial, usina e agrícola podem ter metas diferentes. Se mudar, a conta continua funcionando do mesmo jeito, cada categoria com a sua meta.

**7. Piso de rentabilidade e banda de desconto do representante.** Qual margem mínima o sistema aceita antes de mandar para liberação.

## Uma coisa que vale confirmar junto

Nos custos, tipo de estrutura e região ainda não existem como informação estruturada do pedido. E é justamente aí que mora o custo do pedido pequeno, no deslocamento e em instalar em solo em vez de telhado.

Se essa informação não estiver sendo capturada no pedido hoje, a fase 1 precisa capturar. Sem ela a tabela de instalação fica só na faixa de módulos, que é melhor do que a média de hoje, mas ainda deixa dinheiro na mesa.
