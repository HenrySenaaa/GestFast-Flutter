// Todas as telas, com dados, nas larguras dos breakpoints do style.css do v1 (1100, 900 e 520px) e em volta deles:
// nada pode estourar o layout (faixa amarela e preta) nem lançar exceção. Também com o zoom máximo (150%).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'apoio.dart';
import 'dados_exemplo.dart';

const _telas = ['/painel', '/estoque', '/requisicoes', '/produtos', '/saidas', '/entradas', '/venda', '/historico', '/relatorios', '/funcionarios', '/configuracoes', '/ajuda'];
const _larguras = [1600.0, 1400.0, 1217.0, 1101.0, 1100.0, 1000.0, 901.0, 900.0, 800.0, 600.0, 521.0, 520.0, 420.0, 360.0];

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final tela in _telas) {
    group(tela, () {
      for (final w in _larguras) {
        testWidgets('${w.toInt()}px', (t) async {
          final s = await criarSessao(ApiFalsa(rotasCompletas()));
          await abrirApp(t, s, local: tela, tamanho: Size(w, 900));
          expect(t.takeException(), isNull);
          await encerrar(t);
        });
      }
      testWidgets('zoom de 150%', (t) async {
        SharedPreferences.setMockInitialValues({'gf_zoom': 1.5});
        final s = await criarSessao(ApiFalsa(rotasCompletas()));
        s.zoom = 1.5;
        await abrirApp(t, s, local: tela, tamanho: const Size(1280, 800));
        expect(t.takeException(), isNull);
        await encerrar(t);
      });
    });
  }
}
