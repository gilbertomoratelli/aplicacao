# Como fica a configuração e a operação

## O que é configurável

Tudo isso é por empresa. A configuração da Rudnick não é a mesma da SIC Solar.

### Custos do pedido

Cada custo tem nome, formato de cálculo e a tabela dele. Já entram cadastrados:

| Custo | Formato |
|---|---|
| Instalação | Tabela por faixa de módulos, variando por tipo de estrutura |
| ART | Valor fixo por projeto |
| Homologação | Valor fixo por projeto |
| Deslocamento | Tabela por região ou distância |

Além desses, dá para criar um custo novo a qualquer momento sem depender de desenvolvimento. É o ponto que o Gilberto levantou: se amanhã a operação mudar e aparecer um custo que hoje não existe, é só cadastrar mais um.

### Percentuais

| Percentual | Observação |
|---|---|
| Comissão de representante | Já existe hoje |
| Comissão de coordenador | Já existe hoje |
| Carga tributária | Campo novo |
| Despesa fixa | Campo novo |
| Margem alvo | Campo novo |

### Travas

Margem mínima aceitável, banda de desconto que o representante pode dar sozinho, e arredondamento do preço final.

## Até onde vai a personalização

ART, homologação, instalação e deslocamento não são coisas especiais dentro do sistema. Elas são registros de um tipo genérico de custo, iguais aos que a gente criar depois. Isso é de propósito. Se em algum momento a gente escrever "ART" dentro do código, a personalização morre ali.

A regra é uma só. Tudo que entrar na composição precisa ser uma de duas coisas:

**Um valor em reais**, que entra no custo do pedido. Guindaste, seguro, comissionamento de usina, taxa de cartório.

**Um percentual do preço**, que entra junto com comissão e tributo na fatia que já tem dono.

Isso não é limitação de programação. É o que mantém a conta resolvível de uma vez só, sem ficar rodando em círculo. Se aparecer alguma coisa que não cabe em nenhuma das duas caixas, é sinal de que ela ainda não está bem definida.

### O que dá para criar sem depender de desenvolvimento

| Quero incluir | Como fica |
|---|---|
| Seguro, 0,4% sobre o custo do equipamento | Valor em reais, calculado como percentual de outro custo |
| Guindaste, 1.200, só em estrutura solo | Valor fixo, com condição |
| Comissionamento, 800, só acima de 75 kWp | Valor fixo, com condição |
| Instalação com piso de 1.500 por pedido | Tabela por faixa, com valor mínimo |
| Margem alvo 2 pontos maior no agrícola | Percentual, com condição de linha de negócio |

Em todos esses casos é cadastro, não código.

E o custo novo não fica só no preço. Ele entra sozinho na conta congelada do pedido, no relatório de margem e, se for pagamento a terceiro, no relatório de pagamento.

### O que precisa de um passo a mais

**Percentual que muda conforme o valor do pedido.** Se a comissão for 4% até 100 mil e 3% acima, tem um problema de ordem: para saber a faixa eu preciso do preço, e para saber o preço eu preciso da faixa. Resolve calculando, vendo em que faixa caiu, recalculando, e parando quando o número parar de mudar. São dois ou três passes. É simples, mas precisa estar previsto desde o começo, e por isso a régua de comissão está na lista de perguntas.

**Custo que depende de uma informação que o pedido ainda não captura.** Se eu quiser custo por andar do prédio e "andar" não existe como campo, primeiro precisa existir o campo. O cálculo é o de sempre, o que falta é o dado. É o mesmo motivo pelo qual levantei tipo de estrutura e região.

### A trava que faz isso ser seguro

Configuração livre sem proteção é o jeito mais rápido de quebrar o preço de todo mundo de uma vez.

Antes de publicar qualquer custo novo ou qualquer mudança de tabela, a pessoa vê a simulação em cima dos últimos 12 meses de pedidos: quanto o preço médio muda e quais pedidos passariam a ficar abaixo do piso. Só publica depois de olhar. É a mesma máquina da fase 0, reaproveitada como ferramenta permanente.

E toda mudança tem data de vigência. Vale para frente, nunca para trás.

## Custo interno não é a mesma coisa que serviço

A gente já tem uma aba de serviços no sistema, mas ela não serve para isso, e vale registrar o porquê.

| | Custo interno | Serviço |
|---|---|---|
| Quando entra | Antes, para formar o preço | Depois, somado ao pedido pronto |
| Aparece para o cliente | Não, está embutido no preço | Sim, é linha do pedido |
| É cobrado do cliente | Não | Sim |

A ART é custo interno. A gente não cobra ART do cliente, mas precisa considerar ela para chegar no preço do kit.

Tem um caso de borda para resolver: se em algum pedido a instalação for vendida destacada, como serviço cobrado à parte, ela não pode entrar no custo do kit também. Senão a gente cobra duas vezes. Por isso cada custo vai ter uma marcação dizendo se ele pode ou não ser cobrado destacado, e quando isso acontecer o sistema tira ele da conta do kit automaticamente.

## Quem mexe em quê

| Quem | O que faz |
|---|---|
| Representante | Vê o preço sugerido. Pode dar desconto dentro da banda. Fora da banda vai para liberação |
| Compras | Sobe a planilha de custo. Não sobe mais preço |
| Financeiro | Edita tabelas de custo, tributo, despesa fixa e margem alvo |

O desconto fora da banda reaproveita o fluxo de liberação que já existe hoje para forma de pagamento fora do padrão. Não precisa inventar processo novo.

## Cada pedido guarda a sua própria conta

Quando o pedido é aprovado, o sistema congela dentro dele tudo que foi usado no cálculo: quais custos entraram, qual taxa de cada um, quantos módulos, qual tipo de estrutura, quais percentuais, qual preço saiu e qual preço foi praticado.

Isso não é detalhe, é requisito. Três motivos:

**Se o Gilberto mudar a taxa de instalação em setembro, os pedidos de agosto não podem mudar de número.** É o mesmo princípio dos marcos de conversão que a gente fez no CRM: o dado registrado não muda depois.

**O relatório de pagamento de instalador lê essa conta congelada**, não a configuração atual. Se ler a atual, a gente paga errado.

**Sem isso não dá para reconstituir margem histórica.** Qualquer análise para trás vira chute.

## O ciclo que fecha depois

Cada linha de custo do pedido nasce como previsão. Quando o pagamento acontece de verdade, a gente registra o valor real ao lado da previsão.

A partir daí saem duas coisas: a margem real de cada pedido, e a validação das próprias tabelas de custo. Se a previsão de instalação está sempre abaixo do que a gente paga, a tabela está desatualizada e o sistema mostra isso.

Esse é o ponto onde a precificação encontra o financeiro que a gente discutiu. A ordem importa: precificação primeiro, porque ela gera a previsão. Financeiro depois, porque ele gera o realizado. Ao contrário não fecha.
