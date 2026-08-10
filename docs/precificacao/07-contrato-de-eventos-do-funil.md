# Contrato de eventos do funil

Referência técnica para quem constrói a automação. O documento voltado ao time
que desenha a jornada é o [06](06-regras-de-cadencia-e-automacao.md); este aqui é
o outro lado: o que o sistema manda, com que garantias, e o que precisa ser feito
do lado do n8n.

---

## Os quatro eventos

Todos chegam como `POST` com corpo JSON.

| Evento | Quando | Vai para |
|---|---|---|
| `etapa.timeout` | o lead ficou parado além do tempo daquela etapa | a URL **daquela etapa** |
| `etapa.concluida` | concluiu uma etapa | a URL **única de eventos** |
| `funil.concluido` | chegou ao diagnóstico | a URL única de eventos |
| `cta.clicado` | clicou no botão de WhatsApp | a URL única de eventos |

As URLs são configuradas no painel `/adm` e valem na hora.

### Como ler um `etapa.timeout`

`etapa` diz qual etapa ele **não** concluiu. `funil.etapa_concluida` diz a última
que ele terminou. O par dos dois é o ponto de parada:

| `etapa` | `funil.aguardando` | Ponto de parada (doc 06) |
|---|---|---|
| `projeto` | `etapa` | **B** — deixou o contato |
| `custos` | `etapa` | **C** — preencheu o projeto |
| `diagnostico` | `etapa` | *(sem jornada própria — ver abaixo)* |
| `diagnostico` | `cta_whatsapp` | **D** — viu o resultado e não clicou |

> A etapa `diagnostico` aparece nas duas últimas linhas e o que separa os casos é
> **só** o campo `aguardando`. São leads em temperaturas opostas — o ramo do n8n
> precisa olhar esse campo, não a etapa.

**O caso `diagnostico` + `aguardando: "etapa"`** é o lead que terminou os Custos e
nunca chegou a abrir o resultado. Só acontece se ele fechar o navegador durante o
redirecionamento, que é imediato — na prática é raríssimo. Ele não tem jornada
desenhada no doc 06 de propósito; **rotear para a mesma cadência do ponto C.** O
disparo continua existindo porque o lead é real e contactável: o que não se
justifica é pedir ao time uma jornada inteira para um caso de borda.

---

## Payload

Exemplo real, gerado pelo sistema (`etapa.timeout` na etapa Custos):

```json
{
  "evento": "etapa.timeout",
  "etapa": "custos",
  "etapa_rotulo": "Custos",
  "ocorrido_em": "2026-08-10T21:15:33Z",
  "idempotencia": "ec3b57a4-…:timeout:custos",

  "lead": {
    "sessao": "ec3b57a4-261f-4b05-bc09-7cf7d63ab3e6",
    "integrador_id": "a9698364-56b4-4eed-a827-798a1a91b440",
    "nome_contato": "Maria Silva",
    "nome_empresa": "Solar Norte Energia",
    "cnpj": "11.222.333/0001-81",
    "email": "maria@solarnorte.com.br",
    "whatsapp": "(11) 98765-4321",
    "whatsapp_e164": "+5511987654321",
    "teste": false
  },

  "funil": {
    "etapa_concluida": "projeto",
    "ordem_concluida": 2,
    "total_etapas": 4,
    "parou_em": "custos",
    "aguardando": "etapa",
    "concluiu": false,
    "cta_clicado": false,
    "criado_em": "2026-08-10T20:12:03Z",
    "atualizado_em": "2026-08-10T20:12:41Z",
    "minutos_parado": 63
  },

  "origem": {
    "utm_source": "instagram", "utm_medium": null, "utm_campaign": "agosto",
    "utm_term": null, "utm_content": null,
    "referrer": "https://www.instagram.com/",
    "user_agent": "Mozilla/5.0 …",
    "primeiro_acesso": "2026-08-10T20:11:48Z"
  },

  "dados": {
    "contato": {
      "nome_contato": "Maria Silva", "nome_empresa": "Solar Norte Energia",
      "cnpj": "11.222.333/0001-81", "email": "maria@solarnorte.com.br",
      "whatsapp": "(11) 98765-4321", "regime_tributario": null
    },
    "projeto": {
      "nome_projeto": "10,8 kWp · 24 módulos", "quantidade_modulos": 24,
      "kwp_sistema": 10.8, "custo_kit": 28400, "valor_venda": 52000
    },
    "custos": {
      "despesas": {
        "comissao": { "valor": 5, "base": "total" },
        "tributo":  { "valor": 8, "base": "servico" },
        "notaKit": "distribuidora", "despFixa": 18000, "projetosMes": 6,
        "extras": [], "outras": 0
      },
      "configs": { "campos": { "inst": { "modo": "fixo", "taxa": 4200 }, "…": {} }, "extras": [] },
      "lucro_alvo": 12, "regime_tributario": null
    }
  },

  "diagnostico": null,

  "links": {
    "retomar":   "https://grupofavo.com/precificacao/custos?s=ec3b57a4-…",
    "resultado": "https://grupofavo.com/precificacao/?v=ec3b57a4-…",
    "relatorio": "https://grupofavo.com/precificacao/relatorio?v=ec3b57a4-…",
    "resultado_completo": false
  }
}
```

**`dados`** cresce a cada etapa: só aparecem os blocos que o lead já preencheu.

**`diagnostico`** é `null` até ele chegar à etapa 4. Depois disso traz a linha
inteira de `orcamentos`: custos diretos, entradas comerciais e resultados
calculados (`lucro_mensal`, `margem_contribuicao_pct`, `ponto_equilibrio_qtd`,
`preco_sugerido`).

---

## Os três links

| Campo | Para quem | Efeito colateral |
|---|---|---|
| `links.retomar` (`?s=`) | o **lead** | Reidrata o que ele preencheu e **rearma o relógio** daquela etapa |
| `links.resultado` (`?v=`) | o **vendedor** | Nenhum. Modo consulta: não conta como retomada, não dispara automação, e a aba fica com a escrita travada |
| `links.relatorio` (`?v=`) | o **vendedor** | Idem |

Duas regras que não podem ser trocadas:

- **A mensagem ao lead usa `links.retomar`.** O estado dele está no navegador em
  que ele preencheu; a mensagem quase sempre abre em outro aparelho. Um link sem
  o `?s=` entrega formulário em branco.
- **O card do CRM usa `links.resultado`.** Um vendedor abrindo o card não pode
  reiniciar a cadência de um cliente.

`resultado_completo: false` significa que o lead ainda não chegou ao diagnóstico.
O link abre mesmo assim e mostra o que ele já preencheu.

---

## Garantias

| | |
|---|---|
| **Assinatura** | `X-Funil-Assinatura: sha256=<hmac>` — HMAC-SHA256 do corpo cru, chave no `/adm`. Validar antes de qualquer processamento |
| **Idempotência** | `X-Funil-Idempotencia` e campo `idempotencia`. Entrega é *at-least-once*: deduplicar por essa chave |
| **Retentativa** | 5 tentativas (configurável) com espera crescente: 1 min, 5 min, 15 min, 1 h, 6 h |
| **Indisponibilidade** | A fila segura e reenvia. Nada é perdido por queda curta do n8n |
| **Atraso máximo** | 60 segundos — a fila é varrida de minuto em minuto |
| **Ordem** | **Não garantida.** Usar `ocorrido_em` e `funil.ordem_concluida`, nunca a ordem de chegada |
| **Timeout da requisição** | 10 segundos. Responder 2xx rápido; demora conta como falha e gera reenvio |

Cabeçalhos completos:

```
POST <sua URL>
Content-Type: application/json
X-Funil-Evento: etapa.timeout | etapa.concluida | funil.concluido | cta.clicado
X-Funil-Idempotencia: <chave única>
X-Funil-Assinatura: sha256=<HMAC-SHA256 do corpo cru>
```

---

## Checklist do fluxo no n8n

- [ ] Validar `X-Funil-Assinatura`. Rejeitar se não bater.
- [ ] Deduplicar por `X-Funil-Idempotencia`.
- [ ] Descartar leads com `lead.teste = true`.
- [ ] Em `etapa.timeout`, ramificar por `funil.aguardando` antes de por `etapa`.
- [ ] Em `etapa.concluida`, `funil.concluido` e `cta.clicado`, **cancelar as
      cadências pendentes daquele lead** — é a razão de esses eventos existirem.
- [ ] Checar o estado no CRM e no WhatsApp **antes** de enviar (as regras estão
      no doc 06, P35 a P46).
- [ ] Usar `links.retomar` na mensagem ao lead e `links.resultado` no card do CRM.

---

## Operação

**Painel `/adm`** — senha em bcrypt no banco, definida pelo secret `ADM_SENHA` no
deploy ou uma única vez pelo SQL Editor (`select adm_definir_senha('…')`). Nunca
está no repositório nem chega ao navegador.

- **Configuração**: tempo e URL de webhook por etapa, URL única de eventos, link
  do CTA de WhatsApp, endereço público do site (usado para montar os links),
  número de tentativas e a chave do HMAC. "Testar disparo" enfileira um POST de
  exemplo, com assinatura real, para a URL que você informar.
- **Leads**: quem captou, onde parou, contato, origem, e link para o resultado.
  Exporta CSV.
- **Números**: quantos passaram por cada etapa, quantos travaram em cada uma, e o
  log dos últimos disparos com status HTTP, tentativas e erro.

**O que roda sozinho no banco:** um job de minuto em minuto despacha a fila e
coleta as respostas; um job diário limpa disparos entregues ou cancelados com
mais de 90 dias.

**Um disparo `cancelado`** quase sempre significa que o lead voltou sozinho antes
do tempo — ou que a URL daquela etapa ainda não foi configurada. O motivo fica na
coluna de erro.
