// config.js: Endereço do banco, em um lugar só.
//
// Antes, a URL e a chave do Supabase estavam copiadas nos 9 HTMLs. Trocar de
// ambiente exigia editar os 9 (e bastava esquecer um para a página falar com o
// banco errado). Aqui é um arquivo só, e a escolha é automática:
//
//   rodando em localhost  → Supabase local (supabase start)
//   qualquer outro host   → Supabase de produção
//
// As chaves abaixo são publicáveis (as mesmas que já iam no HTML, visíveis no
// navegador de qualquer visitante). Chave secreta nunca entra aqui.
(function () {
  'use strict';

  var local = ['localhost', '127.0.0.1', '::1', '0.0.0.0'].indexOf(location.hostname) !== -1 ||
              /^192\.168\./.test(location.hostname) ||   // testando pelo celular na rede local
              /^10\./.test(location.hostname);

  window.AppConfig = local
    ? {
        ambiente: 'local',
        // Deriva do próprio host: no Mac vira 127.0.0.1, e ao abrir do celular
        // pelo IP da rede vira esse mesmo IP, que é o único endereço pelo qual
        // o celular consegue enxergar o Supabase rodando na sua máquina.
        supabaseUrl: 'http://' + location.hostname + ':54321',
        supabaseKey: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH'
      }
    : {
        // Banco de PRODUÇÃO desta aplicação (a versão principal).
        // A versão paralela do funil (grupofavo.com/precificacao) usa outro
        // projeto Supabase; não copiar de lá.
        ambiente: 'producao',
        supabaseUrl: 'https://dfsmwzmtainiclcwpigw.supabase.co',
        supabaseKey: 'sb_publishable_trZuSsmSkPKN9Ry0WytyUg_xn7UYBo3'
      };
})();
