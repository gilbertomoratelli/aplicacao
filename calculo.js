// calculo.js — Motor de precificação. Funções puras: recebem números, devolvem
// números. Sem DOM, sem localStorage, sem formatação.
//
// Extraído de index.html para que o diagnóstico e o relatório em PDF usem
// exatamente a mesma conta — antes o relatório recebia um estado já calculado
// por sessionStorage e qualquer divergência passava despercebida.
//
// As fórmulas foram auditadas e mantidas idênticas ao original. As únicas
// mudanças de comportamento estão marcadas com "CORREÇÃO" e são de robustez,
// não de método.
(function () {
  'use strict';

  var Calculo = {};

  // Entrada esperada (todos números; percentuais em pontos, ex.: 6 = 6%):
  //   kit, ca, inst, proj, homol, art   custos diretos por projeto
  //   ticket                            preço praticado hoje
  //   qtd                               projetos por mês
  //   comissao, tributo, outras         percentuais sobre a venda
  //   despFixa                          despesa fixa mensal da empresa
  //   lucroAlvo                         margem líquida desejada (%)
  //   comissaoBase, tributoBase         'total' | 'servico'

  Calculo.custoDiretoTotal = function (d) {
    return (d.kit || 0) + (d.ca || 0) + (d.inst || 0) + (d.proj || 0) + (d.homol || 0) + (d.art || 0);
  };

  // cenario(tk, d) — como fica o negócio se o preço for tk.
  Calculo.cenario = function (tk, d) {
    var cdt = d.cdt != null ? d.cdt : Calculo.custoDiretoTotal(d);

    // CORREÇÃO: trava em zero. Quando o preço é menor que o kit, a base do
    // serviço ficava negativa e o imposto virava receita na DRE.
    var baseServico = Math.max(0, tk - (d.kit || 0));

    var cBase = d.comissaoBase === 'total' ? tk : baseServico;
    var tBase = d.tributoBase === 'total' ? tk : baseServico;

    var comissaoR = (d.comissao || 0) / 100 * cBase;
    var tributoR  = (d.tributo  || 0) / 100 * tBase;
    var outrasR   = (d.outras   || 0) / 100 * tk;

    var dvUnit = comissaoR + tributoR + outrasR;          // despesas variáveis por projeto
    var faturamento = tk * (d.qtd || 0);
    var dvMes = dvUnit * (d.qtd || 0);
    var custoVariavelPct = tk > 0 ? dvUnit / tk : 0;

    var mcUnit = tk - cdt - dvUnit;                        // margem de contribuição
    var mcPct  = tk > 0 ? mcUnit / tk : 0;
    var mcMes  = mcUnit * (d.qtd || 0);

    var despFixaUnit = d.qtd > 0 ? (d.despFixa || 0) / d.qtd : 0;
    var despFixaMes  = d.despFixa || 0;

    var lucroUnit = mcUnit - despFixaUnit;
    var lucroMes  = mcMes - despFixaMes;
    var lucroPct  = tk > 0 ? lucroUnit / tk : 0;

    return {
      ticket: tk, cdt: cdt, baseServico: baseServico,
      comissaoR: comissaoR, tributoR: tributoR, outrasR: outrasR,
      dvUnit: dvUnit, dvMes: dvMes, faturamento: faturamento, custoVariavelPct: custoVariavelPct,
      mcUnit: mcUnit, mcPct: mcPct, mcMes: mcMes,
      despFixaUnit: despFixaUnit, despFixaMes: despFixaMes,
      lucroUnit: lucroUnit, lucroMes: lucroMes, lucroPct: lucroPct
    };
  };

  // precoMinimo(d) — menor preço que ainda entrega a margem alvo.
  //
  // É um PISO, não um alvo: por construção o lucro nele é exatamente lucroAlvo.
  // Todo texto de interface deve chamá-lo de "preço mínimo". Chamá-lo de
  // "sugerido" fez a tela recomendar que integradores baixassem o preço.
  //
  //   abat: quando a base é o serviço, o kit escapa da incidência e essa parcela
  //         volta como abatimento no numerador.
  Calculo.precoMinimo = function (d) {
    var cdt = d.cdt != null ? d.cdt : Calculo.custoDiretoTotal(d);

    var cPctServ = d.comissaoBase === 'servico' ? (d.comissao || 0) / 100 : 0;
    var tPctServ = d.tributoBase  === 'servico' ? (d.tributo  || 0) / 100 : 0;
    var abat = (cPctServ + tPctServ) * (d.kit || 0);

    var baseVar = ((d.comissao || 0) + (d.tributo || 0) + (d.outras || 0)) / 100;
    var denom = 1 - baseVar - (d.lucroAlvo || 0) / 100;

    // Rateio do custo fixo por projeto.
    var fixUnit = d.qtd > 0 ? (d.despFixa || 0) / d.qtd : Infinity;

    if (!isFinite(fixUnit) || denom <= 0) return Infinity;
    return (fixUnit + cdt - abat) / denom;
  };

  // pontoEquilibrio(a) — quantos projetos por mês pagam a estrutura.
  // Sem arredondar: "1,07 projeto" informa; "2" arredondado apagava a diferença
  // entre os cenários e imprimia "2 vs 2".
  Calculo.pontoEquilibrio = function (a) {
    return a.mcUnit > 0 ? a.despFixaMes / a.mcUnit : Infinity;
  };

  // impactoDesconto(d, percentuais) — quanto cada desconto custa por mês.
  // É o argumento comercial da ferramenta: desconto pequeno no preço vira
  // rombo grande no lucro, porque sai inteiro da margem.
  Calculo.impactoDesconto = function (d, percentuais) {
    var base = Calculo.cenario(d.ticket, d);
    return (percentuais || [0, 2, 5, 10]).map(function (p) {
      var preco = d.ticket * (1 - p / 100);
      var c = Calculo.cenario(preco, d);
      return {
        desconto: p,
        preco: preco,
        lucroMes: c.lucroMes,
        perdaMes: base.lucroMes - c.lucroMes,
        // Quantas vezes o desconto se multiplica em perda de lucro.
        multiplicador: p > 0 && base.lucroMes > 0
          ? (base.lucroMes - c.lucroMes) / (base.lucroMes * p / 100)
          : null
      };
    });
  };

  // custoMaximo(d) — maior custo direto por projeto que ainda entrega a margem
  // alvo SEM mexer no preço. É a alternativa honesta a "aumente o preço":
  // muita integradora tem mais espaço para negociar kit e instalação do que
  // para repassar reajuste ao cliente.
  //
  // Assume que a redução vem de custos que não alteram o abatimento fiscal
  // (ou seja, não vem do kit). Se vier do kit, a economia necessária é menor.
  Calculo.custoMaximo = function (d) {
    var cPctServ = d.comissaoBase === 'servico' ? (d.comissao || 0) / 100 : 0;
    var tPctServ = d.tributoBase  === 'servico' ? (d.tributo  || 0) / 100 : 0;
    var abat = (cPctServ + tPctServ) * (d.kit || 0);

    var baseVar = ((d.comissao || 0) + (d.tributo || 0) + (d.outras || 0)) / 100;
    var denom = 1 - baseVar - (d.lucroAlvo || 0) / 100;
    var fixUnit = d.qtd > 0 ? (d.despFixa || 0) / d.qtd : Infinity;

    if (!isFinite(fixUnit)) return null;
    return d.ticket * denom - fixUnit + abat;
  };

  // projecaoAnual(a) — o mesmo cenário esticado para 12 meses.
  Calculo.projecaoAnual = function (a, qtd) {
    return {
      projetos: (qtd || 0) * 12,
      faturamento: a.faturamento * 12,
      margemContribuicao: a.mcMes * 12,
      despesasFixas: a.despFixaMes * 12,
      sobra: a.lucroMes * 12
    };
  };

  // diagnostico(d) — tudo que a tela precisa, em uma chamada.
  Calculo.diagnostico = function (d) {
    var dados = Object.assign({}, d);
    dados.cdt = Calculo.custoDiretoTotal(dados);

    var atual = Calculo.cenario(dados.ticket, dados);
    var piso = Calculo.precoMinimo(dados);
    var cenarioPiso = isFinite(piso) ? Calculo.cenario(piso, dados) : null;

    // CORREÇÃO: a exibição depende do piso ser calculável e do preço informado
    // existir — não da viabilidade do cenário atual. Antes, empresa com estrutura
    // pesada recebia "ajuste a meta" mesmo com o piso corretamente calculado.
    var valido = isFinite(piso) && piso > 0 && dados.ticket > 0;

    // Situação, decidida pelo LUCRO e não pela diferença de preço. Preço acima
    // do piso é folga de margem, não erro a corrigir.
    var situacao;
    if (!valido)                                    situacao = 'indefinido';
    else if (atual.lucroMes < 0)                    situacao = 'prejuizo';
    else if (atual.lucroPct < (dados.lucroAlvo || 0) / 100) situacao = 'abaixo_da_meta';
    else                                            situacao = 'saudavel';

    return {
      dados: dados,
      atual: atual,
      piso: piso,
      cenarioPiso: cenarioPiso,
      valido: valido,
      situacao: situacao,
      abaixoDoPiso: valido && dados.ticket < piso,
      folga: valido ? dados.ticket - piso : null,
      pontoEquilibrio: Calculo.pontoEquilibrio(atual),
      descontos: Calculo.impactoDesconto(dados),
      custoMaximo: Calculo.custoMaximo(dados),
      anual: Calculo.projecaoAnual(atual, dados.qtd)
    };
  };

  if (typeof window !== 'undefined') window.Calculo = Calculo;
  if (typeof module !== 'undefined' && module.exports) module.exports = Calculo;
})();
