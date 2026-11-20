// Gera server/test/golden/js_semantica.json: casos de Number(), String(), toFixed, Math.round,
// trim e JSON.stringify calculados pelo Node, para o js.dart reproduzir exatamente.
const fs = require('fs');
const path = require('path');
const textos = ['', ' ', '12', ' 12 ', '\n\t12 ', '1e3', '1E-3', '.5', '5.', '+5', '-5', '0x10', '0X1f', '0o17', '0b101', '0b2', '0x', '-0x10',
  'Infinity', '-Infinity', '+Infinity', 'infinity', 'NaN', 'abc', '12abc', '1,5', '1.5.5', '00012', '1e400', '-1e400', '1e-400', '  7 　',
  '﻿8', '1_000', '0.1', '2.675', '999999999999999999999', '123456789012345678', '9007199254740993', ' + 5', '--5', 'e5', '5e', '.', '+.', '1e+', '0.0000001',
  '1.7976931348623157e308', '4.9e-324', '0x1fffffffffffff1', '​5', '᠎5'];
const numeros = [0, -0, 1, -1, 0.1, 0.2, 0.1 + 0.2, 1 / 3, 2 / 3, 10, 100, 1e20, 1e21, 1.5e21, 123456789012345680000, 1e-6, 1e-7, 1.5e-7, 0.000001234, 123.456, -123.456,
  5e-324, 1.7976931348623157e308, 9007199254740993, 2 ** 53, 18.9, 16.9 * 6.5, 109.85, 0.30000000000000004, 1234567.891, 0.5, 1.005, 2.675, 1.0005, -2.5, 2.5, -0.5, 0.49999999999999994,
  4.35, 8.345, 1e15 + 0.3, 99999999.995, -1e-7, 7.000000000000001];
const out = {
  number: textos.map(t => [t, String(Number(t))]),
  string: numeros.map(n => [n, String(n)]),
  toFixed2: numeros.map(n => [n, n.toFixed(2)]),
  round: numeros.map(n => [n, String(Math.round(n))]),
  r2: numeros.map(n => [n, String(Math.round((n + Number.EPSILON) * 100) / 100)]),
  r3: numeros.map(n => [n, String(Math.round((n + Number.EPSILON) * 1000) / 1000)]),
  trim: textos.map(t => [t, t.trim()]),
  stringify: ['a"b\c', '\u0000\u001f\b\t\n\f\r', 'ação 😀', '\ud800x', 'x\udc00', '  ', '</script>'].map(s => [s, JSON.stringify(s)]),
  valores: [[[1, 'a', null, true], JSON.stringify([1, 'a', null, true])], [{ a: [1.5, { b: 'c' }], d: -0 }, JSON.stringify({ a: [1.5, { b: 'c' }], d: -0 })]],
  stringOf: [[[1, null, 'a', [2, 3]], String([1, null, 'a', [2, 3]])], [{}, String({})], [[], String([])], [true, String(true)], [null, String(null)]],
  numberOf: [[[], String(Number([]))], [[5], String(Number([5]))], [['7'], String(Number(['7']))], [[1, 2], String(Number([1, 2]))], [{}, String(Number({}))], [true, String(Number(true))], [null, String(Number(null))]]
};
// Os números entram no JSON como texto (String(n)) para preservar -0 e valores especiais.
out.string = out.string.map(([n, s]) => [String(n) === s ? s : s, s]);
for (const k of ['string', 'toFixed2', 'round', 'r2', 'r3']) out[k] = out[k].map(([n, s], i) => [numeros[i].toString(16) === undefined ? '' : numeros[i], s]);
fs.writeFileSync(path.join(__dirname, '..', '..', 'server', 'test', 'golden', 'js_semantica.json'), JSON.stringify(out, null, 1));
console.log('ok', Object.keys(out).map(k => `${k}:${out[k].length}`).join(' '));
