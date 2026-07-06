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

  window.AppCore = AppCore;
})();
