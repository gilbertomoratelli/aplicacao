# Jornada do lead e regras de cadência

**Para quem:** o time que vai desenhar a cadência, o cadastro no Arco CRM e os
fluxos de contato.

Este documento tem duas partes. A primeira explica como o funil funciona, o que
dá para configurar e quais automações são possíveis. A segunda são as seis
perguntas que precisam de resposta para a jornada existir.

---

## Parte 1 — A jornada

### As quatro telas

O lead entra numa página, preenche um formulário curto e clica em “Continuar”.

| | Tela | O que ele preenche |
|---|---|---|
| 1 | **Contato** | nome, CNPJ, empresa, e-mail, WhatsApp |
| 2 | **Projeto** | módulos, potência (kWp), custo do kit, **preço que ele cobra hoje** |
| 3 | **Custos** | projetos por mês, despesa fixa, instalação, comissão, imposto, margem que ele quer |
| 4 | **Diagnóstico** | nada. É a entrega: mostramos se ele está tendo lucro ou prejuízo no preço atual |

No fim da tela 4 aparece um botão de WhatsApp. Clicar nesse botão é a conversão
do funil.

### Onde ele pode parar

| | Onde parou | O que sabemos sobre ele |
|---|---|---|
| **A** | No meio da tela 1, antes de clicar em Continuar | **Nada. Ele é invisível para nós.** |
| **B** | Terminou o Contato, não preencheu o Projeto | Nome, empresa, CNPJ, e-mail, WhatsApp |
| **C** | Terminou o Projeto, não preencheu os Custos | O acima + tamanho do projeto e **quanto ele cobra hoje** |
| **D** | **Viu o resultado e não clicou no WhatsApp** | Tudo + o diagnóstico: lucro, margem, preço mínimo |
| **E** | **Clicou no WhatsApp** | Tudo. Converteu. |

O ponto **A** não gera registro: sem o clique em “Continuar” não existe nome nem
telefone. Os pontos **B**, **C** e **D** são os que a cadência precisa cobrir. O
**E** é a conversão.

### Como o relógio funciona

Cada etapa tem um tempo de inatividade. Se o lead ficar parado além dele sem
avançar, o sistema dispara um aviso. Se ele voltar e avançar antes, o aviso é
cancelado sozinho.

O relógio roda no servidor: **funciona com o navegador dele fechado, o celular
desligado, dias depois.**

---

## Parte 2 — O que é configurável

Tudo abaixo fica num painel interno e vale na hora, sem publicar o site de novo.

| O que | Detalhe |
|---|---|
| **Tempo de inatividade de cada etapa** | Independente por etapa. De minutos a horas |
| **Para onde vai o aviso de cada etapa** | Um destino por etapa, para cada uma ter sua própria cadência |
| **Para onde vão os avisos de avanço** | Um destino único: lead avançou, concluiu o funil, clicou no WhatsApp |
| **Ligar e desligar cada etapa** | Dá para rodar só uma etapa primeiro e ligar as outras depois |
| **O link do WhatsApp do CTA** | Trocar o número de atendimento não exige publicar nada |

O painel também mostra a lista de leads captados com o ponto em que cada um
parou, os números do funil por etapa, e o histórico dos avisos disparados.

---

## Parte 3 — Quais automações podemos fazer

### O que o sistema avisa

| Aviso | Quando dispara |
|---|---|
| **Abandono na etapa** | O lead ficou parado além do tempo configurado. Um aviso por etapa |
| **Avançou de etapa** | A cada etapa concluída |
| **Concluiu o funil** | Chegou ao diagnóstico |
| **Clicou no WhatsApp** | Converteu |

Os três últimos existem para **interromper uma cadência em andamento**: se o lead
volta sozinho, a mensagem de resgate não pode sair.

### O que vem junto em cada aviso

- Nome, empresa, CNPJ, e-mail e WhatsApp
- De onde ele veio: campanha, anúncio, origem
- Tudo que ele preencheu até ali: potência, módulos, custo do kit, **preço que
  pratica**, projetos por mês, despesa fixa, comissão, imposto, margem-alvo
- O diagnóstico calculado, quando ele chegou até lá: lucro mensal, margem, preço
  mínimo, ponto de equilíbrio
- Em que ponto ele parou e há quanto tempo está parado
- **Um link que devolve o lead ao ponto onde parou** — recupera o que ele já
  preencheu mesmo se ele abrir em outro aparelho
- **Um link do resultado para o vendedor**, que abre o diagnóstico do lead sem
  interferir no funil dele. É o que vai no card do CRM

### O que dá para fazer com isso

- Criar ou atualizar o lead no Arco CRM, com os campos que vocês escolherem
- Mover o lead de etapa no CRM conforme ele avança ou trava
- Enviar mensagem de WhatsApp, e-mail, ou os dois
- Criar tarefa para uma pessoa ligar
- Notificar um vendedor específico
- Cancelar uma cadência em andamento quando o lead volta sozinho
- Aplicar qualquer regra de exceção antes de enviar — por exemplo, não mandar
  nada se o telefone já estiver em atendimento

### O que o sistema não sabe

- **Quem abandonou antes de concluir a tela 1.** Não há nome nem telefone.
- **Se o lead chegou a mandar mensagem** depois de clicar no botão de WhatsApp.
  Sabemos só que ele clicou; o resto só o lado do WhatsApp enxerga.
- **O que acontece dentro do CRM e do WhatsApp.** Se a cadência precisa parar
  porque um vendedor agiu, esse sinal tem que vir de lá.

---

## Parte 4 — As perguntas

**P1. Quanto tempo de inatividade para cada etapa?**

| Ponto de parada | Tempo até disparar |
|---|---|
| **B** — deixou o contato | |
| **C** — preencheu o projeto | |
| **D** — viu o resultado e não clicou | |

---

**P2. Para cada etapa: quais mensagens, quantos pontos de contato, e quanto tempo
entre um e outro?**

| Ponto de parada | Nº de contatos | Intervalo entre eles | Canal | Mensagens |
|---|---|---|---|---|
| **B** — deixou o contato | | | | |
| **C** — preencheu o projeto | | | | |
| **D** — viu o resultado e não clicou | | | | |

---

**P3. Os leads ficam visíveis para o vendedor ou SDR desde que entram, ou só
quando nós passarmos para eles?**

Se for só quando passarmos: quem decide o momento, e com base em quê?

---

**P4. O que acontece quando o lead já está em atendimento no WhatsApp com alguém
neste momento?**

A cadência automática dispara mesmo assim? Se não, o que acontece no lugar dela?

---

**P5. O que acontece com leads que já estão no CRM?**

---

**P6. Caso os vendedores tenham acesso ao lead, qualquer ação deles interrompe a
cadência?**

Movimentar de etapa, anotar, marcar uma tarefa — qualquer uma dessas ações
cancela a cadência automática, ou só algumas? Se só algumas, quais?
