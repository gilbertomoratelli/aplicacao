// app-core.js — Fonte ÚNICA de verdade para os helpers compartilhados do app de precificação solar.
// Expõe window.AppCore (IIFE clássica, sem build/modules). Todos os HTMLs devem usar estes helpers em vez de duplicar lógica.
(function () {
  'use strict';

  var AppCore = {};

  // 1. safeParse(key, fallback) — lê localStorage[key] e faz JSON.parse com try/catch.
  //    Se a chave não existir OU o parse falhar, retorna fallback. Nunca lança.
  AppCore.safeParse = function (key, fallback) {
    try {
      var raw = localStorage.getItem(key);
      if (raw === null || raw === undefined) return fallback;
      return JSON.parse(raw);
    } catch (e) {
      return fallback;
    }
  };

  // 2. parseNum(value) — parse robusto de número em formato pt-BR. Aceita string ou number.
  //    Heurística escolhida (entrada humana é o caso dominante):
  //      - number finito → retorna ele mesmo.
  //      - remove tudo que não seja dígito, vírgula, ponto ou "-".
  //      - TEM vírgula → vírgula é decimal; remove todos os pontos (milhar). Ex: "12.500,00" → 12500.
  //      - NÃO tem vírgula mas TEM ponto(s):
  //          * mais de um ponto (ex "1.234.567") → pontos são milhar, remove todos → 1234567.
  //          * um único ponto e o grupo final tem exatamente 3 dígitos (ex "12.500") → milhar → 12500.
  //          * caso contrário (ex "12.5", "12.55") → ponto é decimal → 12.5.
  //      - NaN → 0.
  //    Exemplos: "12.500,00"→12500 ; "1.234.567,89"→1234567.89 ; "12.5"→12.5 ; "1.500"→1500 ; "R$ 3,50"→3.5
  AppCore.parseNum = function (value) {
    if (typeof value === 'number') return isFinite(value) ? value : 0;
    if (value === null || value === undefined) return 0;

    var s = String(value).replace(/[^\d,.\-]/g, '');
    if (!s) return 0;

    if (s.indexOf(',') !== -1) {
      // vírgula = decimal; pontos = milhar
      s = s.replace(/\./g, '').replace(',', '.');
    } else if (s.indexOf('.') !== -1) {
      var dotCount = (s.match(/\./g) || []).length;
      var lastGroup = s.slice(s.lastIndexOf('.') + 1);
      if (dotCount > 1 || lastGroup.length === 3) {
        // milhar
        s = s.replace(/\./g, '');
      }
      // senão: ponto é decimal, mantém como está
    }

    var n = Number(s);
    return isNaN(n) ? 0 : n;
  };

  // 3. escapeHtml(str) — escapa & < > " ' para entidades HTML.
  //    Aceita qualquer tipo (coage para string; null/undefined → "").
  AppCore.escapeHtml = function (str) {
    if (str === null || str === undefined) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  };

  // 4. dbTry(promise) — envolve uma Promise (tipicamente query supabase que já retorna {data,error})
  //    e SEMPRE resolve para { data, error }, nunca rejeita.
  //      - promise rejeita → { data: null, error: <erro> }
  //      - resolve com objeto que já tem {data,error} → repassa
  //      - resolve com outro valor → { data: <valor>, error: null }
  AppCore.dbTry = async function (promise) {
    try {
      var result = await promise;
      if (result && typeof result === 'object' && 'data' in result && 'error' in result) {
        return result;
      }
      return { data: result, error: null };
    } catch (error) {
      return { data: null, error: error };
    }
  };

  // 5. getClient(url, key) — cria/retorna (memoizado) o client Supabase.
  //    Se window.supabase (SDK global da CDN) NÃO existir, retorna null SEM lançar,
  //    impedindo que a página morra quando a CDN cai/está offline.
  var _client = null;
  AppCore.getClient = function (url, key) {
    if (_client) return _client;
    if (!window.supabase || typeof window.supabase.createClient !== 'function') {
      return null;
    }
    _client = window.supabase.createClient(url, key);
    return _client;
  };

  // 6. uuid() — retorna crypto.randomUUID() se disponível; senão fallback timestamp+random.
  //    Para ids gerados client-side.
  AppCore.uuid = function () {
    if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
      return crypto.randomUUID();
    }
    return 'id-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 10);
  };

  // 7. PASSOS — fonte ÚNICA do funil de captação.
  //    A ordem do array É a ordem do funil. Para mudar o funil (adicionar, remover
  //    ou reordenar etapa) edita-se SÓ esta lista: o stepper de todas as páginas
  //    é derivado daqui, então não existe marcação de passo duplicada em HTML.
  //      id     — identificador da etapa, usado pela página para se localizar.
  //      rotulo — texto curto exibido no desktop (cabe embaixo do círculo).
  //      href   — destino ao clicar numa etapa já concluída.
  AppCore.PASSOS = [
    { id: 'empresa',      rotulo: 'Empresa',   href: 'cadastro.html' },
    { id: 'custos',       rotulo: 'Custos',    href: 'configuracoes.html?onboarding=1' },
    { id: 'despesas',     rotulo: 'Despesas',  href: 'despesas.html' },
    { id: 'sazonalidade', rotulo: 'Sazonal.',  href: 'sazonalidade.html' },
    { id: 'indicadores',  rotulo: 'Indicad.',  href: 'indicadores.html' },
    { id: 'projeto',      rotulo: 'Projeto',   href: 'projeto.html' },
    { id: 'preco',        rotulo: 'Preço',     href: 'index.html' }
  ];

  // 8. renderStepper(container, passoAtualId) — desenha o indicador de progresso.
  //    Emite as DUAS versões (compacta e completa); o shared.css escolhe qual
  //    aparece conforme a largura da tela, sem depender de JS de resize.
  //
  //    Regras de navegação (decisão de UX, não acidente):
  //      - etapa concluída  → link real (<a>), dá para voltar e corrigir.
  //      - etapa atual      → não é link, marcada com aria-current="step".
  //      - etapa futura     → NÃO é clicável: pular etapa adiante levaria o
  //                           usuário a uma tela sem os dados que ela exige.
  AppCore.renderStepper = function (container, passoAtualId) {
    var el = typeof container === 'string' ? document.getElementById(container) : container;
    if (!el) return;

    var passos = AppCore.PASSOS;
    var atual = -1;
    for (var i = 0; i < passos.length; i++) {
      if (passos[i].id === passoAtualId) { atual = i; break; }
    }
    if (atual === -1) return;

    var esc = AppCore.escapeHtml;
    var total = passos.length;
    var posicao = atual + 1;
    var pctConcluido = Math.round((posicao / total) * 1000) / 10;

    // Versão compacta: "Passo 2 de 7" + nome da etapa + barra de progresso.
    var compacta =
      '<div class="stepper-compact">' +
        '<div class="sc-head">' +
          '<span class="sc-count">Passo ' + posicao + ' de ' + total + '</span>' +
          '<span class="sc-name">' + esc(passos[atual].rotulo) + '</span>' +
        '</div>' +
        '<div class="sc-bar"><div class="sc-fill" style="width:' + pctConcluido + '%"></div></div>' +
      '</div>';

    // Versão completa: círculo + rótulo por etapa, ligados por linha.
    var itens = [];
    for (var j = 0; j < total; j++) {
      var p = passos[j];
      var concluido = j < atual;
      var ehAtual = j === atual;
      var classe = concluido ? 'step done' : (ehAtual ? 'step active' : 'step');
      var simbolo = concluido ? '✓' : String(j + 1);
      var miolo = '<span class="sn" aria-hidden="true">' + simbolo + '</span>' +
                  '<span class="sl">' + esc(p.rotulo) + '</span>';

      if (j > 0) {
        itens.push('<li class="sline' + (concluido || ehAtual ? ' done' : '') + '" aria-hidden="true"></li>');
      }

      if (concluido) {
        itens.push(
          '<li class="' + classe + '">' +
            '<a class="step-link" href="' + esc(p.href) + '">' +
              miolo + '<span class="sr-only">(etapa concluída — clique para revisar)</span>' +
            '</a>' +
          '</li>'
        );
      } else {
        itens.push(
          '<li class="' + classe + '"' + (ehAtual ? ' aria-current="step"' : '') + '>' +
            '<span class="step-link">' + miolo + '</span>' +
          '</li>'
        );
      }
    }

    el.className = 'stepper';
    el.innerHTML = compacta + '<ol class="stepper-full">' + itens.join('') + '</ol>';
    if (!el.getAttribute('aria-label')) el.setAttribute('aria-label', 'Progresso do cadastro');
  };

  // 9. validarCampos(campos) — validação declarativa de formulário, usada por
  //    todas as telas do funil (antes cada página repetia o mesmo laço).
  //    Cada item da lista descreve UM campo:
  //      id    — id do <input>/<select>.
  //      err   — id do elemento que exibe a mensagem de erro.
  //      check — (valor) => boolean. Verdadeiro quando o campo está válido.
  //      msg   — opcional. (valor) => texto do erro. Recebe o valor para poder
  //              diferenciar "não preencheu" de "preencheu errado". Se omitido,
  //              mantém o texto que já estiver no HTML.
  //    Além de marcar os erros, foca e rola até o PRIMEIRO campo inválido: no
  //    celular o formulário não cabe todo na tela e, sem isso, o usuário clica
  //    em "Continuar" e nada parece acontecer.
  //    Retorna true quando todos os campos passaram.
  AppCore.validarCampos = function (campos) {
    var primeiroInvalido = null;

    campos.forEach(function (c) {
      var el = document.getElementById(c.id);
      var errEl = document.getElementById(c.err);
      if (!el) return;

      var valido = c.check(el.value);

      if (errEl) {
        if (!valido && typeof c.msg === 'function') errEl.textContent = c.msg(el.value);
        errEl.style.display = valido ? 'none' : 'block';
      }
      el.setAttribute('aria-invalid', valido ? 'false' : 'true');
      if (!valido && !primeiroInvalido) primeiroInvalido = el;
    });

    if (primeiroInvalido) {
      primeiroInvalido.focus({ preventScroll: true });
      // scrollIntoView não existe em todo ambiente (ex.: jsdom nos testes);
      // rolar é um conforto, não pode derrubar a validação.
      if (typeof primeiroInvalido.scrollIntoView === 'function') {
        primeiroInvalido.scrollIntoView({ block: 'center', behavior: 'smooth' });
      }
    }
    return !primeiroInvalido;
  };

  window.AppCore = AppCore;
})();
