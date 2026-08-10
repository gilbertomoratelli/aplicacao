// app-core.js: Fonte ÚNICA de verdade para os helpers compartilhados do app de precificação solar.
// Expõe window.AppCore (IIFE clássica, sem build/modules). Todos os HTMLs devem usar estes helpers em vez de duplicar lógica.
(function () {
  'use strict';

  var AppCore = {};

  // Prazo máximo (ms) para consultas feitas durante a abertura de uma tela.
  // Passado esse tempo, seguimos com o dado local: é melhor mostrar o que já
  // temos do que travar a tela esperando o servidor.
  AppCore.PRAZO_BOOT = 6000;

  // 1. safeParse(key, fallback): lê localStorage[key] e faz JSON.parse com try/catch.
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

  // 2. parseNum(value): parse robusto de número em formato pt-BR. Aceita string ou number.
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

  // 3. escapeHtml(str): escapa & < > " ' para entidades HTML.
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

  // 4. dbTry(promise, prazoMs): envolve uma Promise (tipicamente query supabase
  //    que já retorna {data,error}) e SEMPRE resolve para { data, error }, nunca rejeita.
  //      - promise rejeita → { data: null, error: <erro> }
  //      - resolve com objeto que já tem {data,error} → repassa
  //      - resolve com outro valor → { data: <valor>, error: null }
  //    prazoMs (opcional): desiste da espera e devolve erro de tempo esgotado.
  //    Serve para chamadas que rodam durante a abertura da tela: rede lenta não
  //    pode segurar o carregamento e deixar o usuário vendo valor padrão como se
  //    fosse o dado dele. A promise original segue seu curso; só paramos de esperar.
  AppCore.dbTry = async function (promise, prazoMs) {
    try {
      var result;
      if (prazoMs) {
        var expirou = { __prazoEsgotado: true };
        result = await Promise.race([
          promise,
          new Promise(function (resolve) { setTimeout(function () { resolve(expirou); }, prazoMs); })
        ]);
        if (result === expirou) {
          return { data: null, error: new Error('Tempo esgotado ao consultar o servidor') };
        }
      } else {
        result = await promise;
      }
      if (result && typeof result === 'object' && 'data' in result && 'error' in result) {
        return result;
      }
      return { data: result, error: null };
    } catch (error) {
      return { data: null, error: error };
    }
  };

  // 5. getClient(url, key): cria/retorna (memoizado) o client Supabase.
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

  // 6. uuid(): retorna crypto.randomUUID() se disponível; senão fallback timestamp+random.
  //    Para ids gerados client-side.
  AppCore.uuid = function () {
    if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
      return crypto.randomUUID();
    }
    return 'id-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 10);
  };

  // 7. PASSOS: fonte ÚNICA do funil de captação.
  //    A ordem do array É a ordem do funil. Para mudar o funil (adicionar, remover
  //    ou reordenar etapa) edita-se SÓ esta lista: o stepper de todas as páginas
  //    é derivado daqui, então não existe marcação de passo duplicada em HTML.
  //      id:     identificador da etapa, usado pela página para se localizar.
  //      rotulo: texto curto exibido no desktop (cabe embaixo do círculo).
  //      href:   destino ao clicar numa etapa já concluída.
  //    Projeto vem ANTES de Custos de propósito: a tela de custos calcula prévias
  //    ("quanto isso dá no seu projeto?") e, com o projeto já preenchido, ela usa
  //    os números reais do usuário em vez de uma referência genérica.
  AppCore.PASSOS = [
    { id: 'contato',    rotulo: 'Contato',     href: 'cadastro.html' },
    { id: 'projeto',    rotulo: 'Projeto',     href: 'projeto.html' },
    { id: 'custos',     rotulo: 'Custos',      href: 'custos.html' },
    { id: 'diagnostico',rotulo: 'Diagnóstico', href: 'index.html' }
  ];

  // 8. renderStepper(container, passoAtualId): desenha o indicador de progresso.
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
              miolo + '<span class="sr-only">(etapa concluída, clique para revisar)</span>' +
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

  // 9. validarCampos(campos): validação declarativa de formulário, usada por
  //    todas as telas do funil (antes cada página repetia o mesmo laço).
  //    Cada item da lista descreve UM campo:
  //      id:    id do <input>/<select>.
  //      err:   id do elemento que exibe a mensagem de erro.
  //      check: (valor) => boolean. Verdadeiro quando o campo está válido.
  //      msg:   opcional. (valor) => texto do erro. Recebe o valor para poder
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

  // 10. Máscara monetária.
  //     Regra: o dígito digitado entra SEMPRE na parte inteira, à frente da
  //     vírgula. É o oposto da máscara "de caixa eletrônico", em que digitar
  //     1-2-5-0 produz 12,50 — ali o usuário que quer R$ 1.250,00 precisa
  //     digitar seis teclas e torcer. Aqui ele digita 1250 e lê 1.250; se
  //     quiser centavos, digita a vírgula (ou navega até depois dela) e
  //     continua. Como quase todo valor deste app é redondo, isso elimina a
  //     digitação de dois zeros em cada campo.
  //
  //     formatarMoeda opera sobre TEXTO, não sobre número: preservar o que o
  //     usuário está no meio de digitar (inclusive "1.250," sem centavos
  //     ainda) é o que evita o campo brigar com o teclado.
  AppCore.formatarMoeda = function (bruto) {
    var texto = String(bruto == null ? '' : bruto);
    var virgula = texto.indexOf(',');

    var inteiro = virgula === -1 ? texto : texto.slice(0, virgula);
    var decimal = virgula === -1 ? ''    : texto.slice(virgula + 1);

    // Zeros à esquerda somem, mas "0" sozinho fica: digitar 0 é intenção.
    inteiro = inteiro.replace(/\D/g, '').replace(/^0+(?=\d)/, '');
    decimal = decimal.replace(/\D/g, '').slice(0, 2);

    var agrupado = inteiro ? inteiro.replace(/\B(?=(\d{3})+(?!\d))/g, '.') : '';

    if (virgula === -1) return agrupado;
    return (agrupado || '0') + ',' + decimal;
  };

  // Reformata mantendo o cursor onde o usuário o deixou. Sem isto, inserir um
  // separador de milhar joga o cursor para o fim e digitar vira um sofrimento.
  // A âncora é a QUANTIDADE DE DÍGITOS antes do cursor, não a posição em
  // caracteres: pontos aparecem e desaparecem, dígitos não.
  AppCore.mascaraMoeda = function (el) {
    if (!el) return;
    var antes = el.value;
    var pos = typeof el.selectionStart === 'number' ? el.selectionStart : antes.length;
    var digitosAntes = (antes.slice(0, pos).match(/\d/g) || []).length;

    var depois = AppCore.formatarMoeda(antes);
    if (depois === antes) return;
    el.value = depois;

    var novaPos;
    if (digitosAntes === 0) {
      // Só a vírgula foi digitada: o cursor tem de ficar depois dela.
      novaPos = depois.slice(-1) === ',' ? depois.length : 0;
    } else {
      novaPos = depois.length;
      var contados = 0;
      for (var i = 0; i < depois.length; i++) {
        if (depois.charCodeAt(i) >= 48 && depois.charCodeAt(i) <= 57) {
          contados++;
          if (contados === digitosAntes) { novaPos = i + 1; break; }
        }
      }
    }
    if (typeof el.setSelectionRange === 'function') {
      try { el.setSelectionRange(novaPos, novaPos); } catch (e) {}
    }
  };

  // Ao sair do campo, completa os centavos. Durante a digitação isso seria
  // hostil (o campo mexeria sozinho); ao sair, é só arrumar a casa.
  AppCore.normalizarMoeda = function (el) {
    if (!el || !el.value.trim()) return;
    var n = AppCore.parseNum(el.value);
    el.value = n.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  };

  // Liga a máscara em todo input[data-moeda] dentro de raiz (padrão: document).
  // Idempotente: pode ser chamada de novo depois de injetar campos por JS.
  AppCore.ligarMoeda = function (raiz) {
    var alvo = raiz || document;
    var campos = alvo.querySelectorAll('input[data-moeda]');
    for (var i = 0; i < campos.length; i++) {
      (function (el) {
        if (el.dataset.moedaLigada === '1') return;
        el.dataset.moedaLigada = '1';
        el.setAttribute('inputmode', 'decimal');
        el.addEventListener('input', function () { AppCore.mascaraMoeda(el); });
        el.addEventListener('blur',  function () { AppCore.normalizarMoeda(el); });
      })(campos[i]);
    }
  };

  // 11. Seleção em folha (bottom sheet) no celular.
  //     O <select> nativo abre um seletor de sistema que ignora o desenho da
  //     tela inteira e, no Android, costuma ser um diálogo cinza. Numa tela
  //     que é toda lista agrupada, isso quebra a leitura.
  //
  //     O <select> continua no DOM e continua sendo a fonte da verdade — quem
  //     lê `.value` não sabe que existe folha. No celular ele é escondido por
  //     CSS e um botão desenhado ocupa o lugar; a folha escreve de volta no
  //     select e dispara 'change', então qualquer listener existente continua
  //     funcionando.
  var folhaAberta = null;

  function fecharFolha() {
    if (!folhaAberta) return;
    var ov = folhaAberta.ov, gatilho = folhaAberta.gatilho;
    ov.classList.remove('open');
    folhaAberta = null;
    setTimeout(function () { if (ov.parentNode) ov.parentNode.removeChild(ov); }, 260);
    if (gatilho) gatilho.focus();
  }

  function abrirFolha(sel, gatilho, titulo) {
    var ov = document.createElement('div');
    ov.className = 'modal-ov';
    ov.setAttribute('role', 'dialog');
    ov.setAttribute('aria-modal', 'true');

    var opcoes = '';
    for (var i = 0; i < sel.options.length; i++) {
      var o = sel.options[i];
      // A opção vazia existe só como estado inicial do campo; dentro da folha
      // ela não é uma alternativa e não deve aparecer.
      if (o.disabled || o.hidden || o.value === '') continue;
      opcoes +=
        '<button type="button" class="linha tocavel opcao' + (o.selected ? ' escolhida' : '') + '" ' +
        'data-i="' + i + '" role="option" aria-selected="' + (o.selected ? 'true' : 'false') + '">' +
          '<span class="rot">' + AppCore.escapeHtml(o.textContent) + '</span>' +
          '<span class="vazio"></span><span class="tique" aria-hidden="true"></span>' +
        '</button>';
    }

    ov.innerHTML =
      '<div class="modal-card">' +
        '<div class="modal-head"><h3>' + AppCore.escapeHtml(titulo) + '</h3>' +
          '<button type="button" class="btn-close" aria-label="Fechar">&times;</button></div>' +
        '<div class="lista opcoes" role="listbox">' + opcoes + '</div>' +
      '</div>';

    document.body.appendChild(ov);
    // Um quadro de atraso para a transição de entrada existir: aplicada no
    // mesmo quadro da inserção, o navegador pula a animação.
    requestAnimationFrame(function () { ov.classList.add('open'); });
    folhaAberta = { ov: ov, gatilho: gatilho };

    ov.addEventListener('click', function (e) {
      if (e.target === ov || e.target.closest('.btn-close')) { fecharFolha(); return; }
      var op = e.target.closest('.opcao');
      if (!op) return;
      sel.selectedIndex = parseInt(op.dataset.i, 10);
      sel.dispatchEvent(new Event('change', { bubbles: true }));
      AppCore.sincronizarFolhaSelect(sel);
      fecharFolha();
    });

    document.addEventListener('keydown', function esc(e) {
      if (e.key === 'Escape') { fecharFolha(); document.removeEventListener('keydown', esc); }
    });
  }

  // Mantém o texto do botão igual à opção escolhida no select.
  AppCore.sincronizarFolhaSelect = function (sel) {
    var botao = sel.parentNode && sel.parentNode.querySelector('.abre-folha');
    if (!botao) return;
    var op = sel.options[sel.selectedIndex];
    botao.querySelector('.val').textContent = op ? op.textContent : '';
    // Enquanto nada foi escolhido, o texto é marcador de lugar, não valor.
    botao.classList.toggle('vazio-sel', !sel.value);
  };

  AppCore.ligarFolhaSelect = function (raiz) {
    var alvo = raiz || document;
    var selects = alvo.querySelectorAll('select[data-folha]');
    for (var i = 0; i < selects.length; i++) {
      (function (sel) {
        if (sel.dataset.folhaLigada === '1') return;
        sel.dataset.folhaLigada = '1';

        var linha = sel.closest('.linha');
        var rot = linha && linha.querySelector('.rot');
        var titulo = sel.dataset.folha || (rot ? rot.textContent.replace('*', '').trim() : 'Escolha');

        var botao = document.createElement('button');
        botao.type = 'button';
        botao.className = 'abre-folha';
        botao.innerHTML = '<span class="val"></span><span class="chev" aria-hidden="true"></span>';
        botao.setAttribute('aria-haspopup', 'listbox');
        sel.parentNode.insertBefore(botao, sel.nextSibling);

        botao.addEventListener('click', function () { abrirFolha(sel, botao, titulo); });
        sel.addEventListener('change', function () { AppCore.sincronizarFolhaSelect(sel); });
        AppCore.sincronizarFolhaSelect(sel);
      })(selects[i]);
    }
  };

  window.AppCore = AppCore;
})();
