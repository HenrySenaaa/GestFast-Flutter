// lib/limiter.js - Limite de tentativas (login e senha de gerente), com limpeza de entradas antigas
const { HttpError } = require('./errors');

function criarLimitador({ max = 5, bloqueioMs = 60000, janelaMs = 15 * 60000, relogio = Date.now } = {}) {
  const entradas = new Map();
  const limpar = agora => {
    for (const [k, t] of entradas) if (t.ate <= agora && t.ultima + janelaMs <= agora) entradas.delete(k);
  };
  return {
    checar(chave) {
      const t = entradas.get(chave);
      const agora = relogio();
      if (t && t.ate > agora) throw new HttpError(429, `Muitas tentativas. Aguarde ${Math.ceil((t.ate - agora) / 1000)}s para tentar novamente.`);
    },
    falhou(chave) {
      const agora = relogio();
      limpar(agora);
      const t = entradas.get(chave) || { n: 0, ate: 0, ultima: agora };
      t.n++;
      t.ultima = agora;
      if (t.n >= max) { t.ate = agora + bloqueioMs; t.n = 0; }
      entradas.set(chave, t);
    },
    sucesso(chave) { entradas.delete(chave); },
    tamanho() { return entradas.size; }
  };
}

module.exports = { criarLimitador };
