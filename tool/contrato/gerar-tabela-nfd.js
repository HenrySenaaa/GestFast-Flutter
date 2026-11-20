// Gera server/lib/src/largura_nfd.dart: para cada caractere cuja largura no PDF muda por causa
// do normalize('NFD') + remoção de acentos (lib/export.js do Node), a largura em milésimos.
// Fora da tabela: ASCII 32-126 usa a tabela Helvetica e o resto vale 556.
const fs = require('fs');
const path = require('path');
const HELV = [278,278,355,556,556,889,667,191,333,333,389,584,278,333,278,278,556,556,556,556,556,556,556,556,556,556,278,278,584,584,584,556,1015,667,667,722,722,667,611,778,722,278,500,667,556,833,722,778,667,778,722,667,611,722,667,944,667,667,611,278,278,278,469,556,333,556,556,500,556,556,278,556,556,222,222,500,222,833,556,556,556,556,333,500,278,556,500,722,500,500,500,334,260,334,584];
const base = ch => ch.normalize('NFD').replace(/[̀-ͯ]/g, '');
const w = s => { let t = 0; for (const ch of base(s)) { const c = ch.charCodeAt(0); t += (c >= 32 && c <= 126 ? HELV[c - 32] : 556); } return t; };
const padrao = cp => (cp >= 32 && cp <= 126 ? HELV[cp - 32] : 556);
const pares = [];
for (let cp = 0; cp <= 0x10ffff; cp++) {
  if (cp >= 0xd800 && cp <= 0xdfff) continue;
  const v = w(String.fromCodePoint(cp));
  if (v !== padrao(cp)) pares.push([cp, v]);
}
// Agrupa sequências com a mesma largura e códigos consecutivos: [início, fim, largura].
const faixas = [];
for (const [cp, v] of pares) {
  const u = faixas[faixas.length - 1];
  if (u && u[1] === cp - 1 && u[2] === v) u[1] = cp; else faixas.push([cp, cp, v]);
}
const linhas = faixas.map(f => `  0x${f[0].toString(16)}, 0x${f[1].toString(16)}, ${f[2]},`);
const dart = `// largura_nfd.dart - GERADO por tool/contrato/gerar-tabela-nfd.js (Node ${process.version}, ICU ${process.versions.icu}, Unicode ${process.versions.unicode}).
// Não editar à mão. Larguras (em milésimos do tamanho da fonte) dos caracteres que mudam com
// normalize('NFD') + remoção de acentos, como o lib/export.js do Node media o texto do PDF.
// Trios: primeiro código, último código, largura.
const List<int> faixasNfd = [
${linhas.join('\n')}
];
`;
fs.writeFileSync(path.join(__dirname, '..', '..', 'server', 'lib', 'src', 'largura_nfd.dart'), dart);
console.log('pares', pares.length, 'faixas', faixas.length);
