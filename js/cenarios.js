// cenarios.js — projeções anuais para o Relatório de Diagnóstico
//
// API pública:
//   calcCenarios(params) → { atual, sugerido, necessario, FixasAno, V12 }
//
// Estrutura de cada cenário:
//   { nome, ticket, totalProj, fatAnual, mcAnual, mcPct,
//     lucroAnual, lucroPct, mePE, mesesCalc }
//
// "necessario" adiciona: VnecFat, VnecProj
//   Fórmula: V_nec = FixasAno / (MC% − lucroAlvo%)
//   Premissa: custos fixos não variam com o volume.
//
// Parâmetros esperados em "params":
//   d             — { kit, cdt, ticket, comissao, tributo, outras, despFixa, lucroAlvo }
//   precoSugerido — calculado em render(); pode ser Infinity
//   V12           — projetos/ano da sazonalidade (ou d.qtd × 12 como fallback)
//   meses         — { m01:{projetos,valor}, …, m12 } ou null
//   comissaoBase  — "total" | "servico"
//   tributoBase   — "total" | "servico"
//   despesasExtras — [{ id, nome, valor(%), base("total"|"servico") }]

function calcCenarios(params) {
  const { d, precoSugerido, V12, meses, comissaoBase, tributoBase, despesasExtras } = params;

  const FixasAno   = d.despFixa * 12;
  const props      = _proporcoes(meses);
  const econ       = tk => _unitEcon(tk, d, comissaoBase, tributoBase, despesasExtras);

  const econAtual  = econ(d.ticket);
  const atual      = _projetar('atual', d.ticket, econAtual, V12, FixasAno, props);

  let sugerido = null;
  if (isFinite(precoSugerido) && precoSugerido > 0) {
    sugerido = _projetar('sugerido', precoSugerido, econ(precoSugerido), V12, FixasAno, props);
  }

  // Cenário Necessário: volume mínimo ao preço atual para atingir lucroAlvo%
  let necessario = null;
  const targetPct = d.lucroAlvo / 100;
  if (econAtual.mcPct - targetPct > 0.001) {
    const VnecFat   = FixasAno / (econAtual.mcPct - targetPct);
    const VnecProj  = d.ticket > 0 ? VnecFat / d.ticket : 0;
    necessario            = _projetar('necessario', d.ticket, econAtual, VnecProj, FixasAno, props);
    necessario.VnecFat  = VnecFat;
    necessario.VnecProj = VnecProj;
  }

  return { atual, sugerido, necessario, FixasAno, V12 };
}

// ── Funções internas ──────────────────────────────────────────────────

function _proporcoes(meses) {
  if (!meses || !Object.keys(meses).length) return Array(12).fill(1 / 12);
  const keys  = Object.keys(meses).sort(); // m01 … m12
  const vals  = keys.map(k => parseFloat(meses[k].projetos) || 0);
  const total = vals.reduce((s, v) => s + v, 0);
  if (total === 0) return Array(12).fill(1 / 12);
  return vals.map(v => v / total);
}

function _unitEcon(tk, d, comissaoBase, tributoBase, despesasExtras) {
  const srv       = tk - d.kit;
  const cBase     = comissaoBase === 'total' ? tk : srv;
  const tBase     = tributoBase  === 'total' ? tk : srv;
  const comissaoR = d.comissao / 100 * cBase;
  const tributoR  = d.tributo  / 100 * tBase;
  const outrasR   = d.outras   / 100 * tk;
  const extrasR   = (despesasExtras || []).reduce((s, e) => {
    const base = e.base === 'servico' ? srv : tk;
    return s + (parseFloat(e.valor) || 0) / 100 * base;
  }, 0);
  const dvUnit = comissaoR + tributoR + outrasR + extrasR;
  const mcUnit = tk - d.cdt - dvUnit;
  const mcPct  = tk > 0 ? mcUnit / tk : 0;
  return { comissaoR, tributoR, outrasR, extrasR, dvUnit, mcUnit, mcPct };
}

function _projetar(nome, ticket, econ, totalProj, FixasAno, props) {
  const mesesCalc = props.map(p => {
    const projMes = totalProj * p;
    return { projMes, fatMes: ticket * projMes, mcMes: econ.mcUnit * projMes };
  });

  const fatAnual   = mesesCalc.reduce((s, m) => s + m.fatMes, 0);
  const mcAnual    = mesesCalc.reduce((s, m) => s + m.mcMes, 0);
  const lucroAnual = mcAnual - FixasAno;

  // mePE: primeiro mês em que a MC acumulada cobre as fixas anuais
  let cumMC = 0, mePE = null;
  for (let i = 0; i < 12; i++) {
    cumMC += mesesCalc[i].mcMes;
    if (mePE === null && cumMC >= FixasAno) mePE = i + 1; // 1 = jan
  }

  return {
    nome, ticket, totalProj,
    fatAnual, mcAnual,
    mcPct: econ.mcPct,
    lucroAnual,
    lucroPct: fatAnual > 0 ? lucroAnual / fatAnual : 0,
    mePE,
    mesesCalc,
  };
}

// ── Verificação (rode testCenarios() no console do navegador) ─────────

function testCenarios() {
  const near = (a, b, tol) => Math.abs(a - b) <= (tol || 1);

  // Cenário de referência:
  //   ticket=20000, kit=12000, cdt=14000, comissao=5%/total, tributo=6%/servico
  //   despFixa=10000/mês → FixasAno=120000, V12=24, lucroAlvo=10%
  //
  // Resultado esperado:
  //   comissaoR = 1000, tributoR = 480, dvUnit = 1480
  //   mcUnit = 4520, mcPct = 22,6%
  //   fatAnual = 480000, mcAnual = 108480, lucroAnual = -11520 (prejuízo)
  //   mePE = null (MC/ano < FixasAno)
  //   VnecFat ≈ 952381, VnecProj ≈ 47,62, mePE necessario = 7

  const r = calcCenarios({
    d: { kit:12000, cdt:14000, ticket:20000, comissao:5, tributo:6, outras:0, despFixa:10000, lucroAlvo:10 },
    precoSugerido: Infinity,
    V12: 24,
    meses: null,
    comissaoBase: 'total',
    tributoBase: 'servico',
    despesasExtras: [],
  });

  console.assert(near(r.atual.mcPct, 0.226, 0.001),  'mcPct deve ser ≈22,6%');
  console.assert(near(r.atual.fatAnual,  480000),     'fatAnual deve ser 480000');
  console.assert(near(r.atual.mcAnual,   108480),     'mcAnual deve ser 108480');
  console.assert(near(r.atual.lucroAnual, -11520),    'lucroAnual deve ser -11520');
  console.assert(r.atual.mePE === null,               'mePE deve ser null (prejuízo)');

  console.assert(r.sugerido === null,                 'sugerido deve ser null (precoSugerido=Infinity)');

  const nec = r.necessario;
  console.assert(nec !== null,                        'cenário necessário deve existir');
  console.assert(near(nec.VnecFat, 120000/0.126, 100), 'VnecFat deve ser ≈952381');
  console.assert(near(nec.lucroPct, 0.10, 0.001),    'lucroPct necessário deve ser ≈10%');
  console.assert(nec.mePE === 7,                      'mePE necessário deve ser mês 7');

  console.log('%c✓ testCenarios: todos os assertions passaram', 'color:#00B140;font-weight:700', r);
  return r;
}
