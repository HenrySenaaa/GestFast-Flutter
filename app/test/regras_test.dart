import 'package:flutter_test/flutter_test.dart';
import 'package:gestfast/core/regras.dart';
import 'package:gestfast/features/carrinho.dart';
import 'package:gestfast/models/modelos.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'apoio.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  group('formatação', () {
    test('moeda e quantidade em pt-BR', () {
      expect(dinheiro(1234.5), 'R\$ 1.234,50');
      expect(num2(2), '2,00');
      expect(quantidade(1.5), '1,5');
      expect(quantidade(10), '10');
    });
    test('datas', () {
      expect(dataBR('2026-11-03'), '03/11/2026');
      expect(dataBR('2026-11-03 14:30'), '03/11/2026 14:30');
      expect(dataBR(''), '-');
      expect(somarDias('2026-12-30', 4), '2027-01-03');
    });
    test('número digitado aceita vírgula, ponto e milhar', () {
      expect(lerNumero('1,5'), 1.5);
      expect(lerNumero('1.5'), 1.5);
      expect(lerNumero('1.234,56'), 1234.56);
      expect(lerNumero('abc'), isNull);
      expect(lerNumero(''), isNull);
    });
  });

  group('regras', () {
    test('só KG e Lt aceitam fração', () {
      expect(erroQuantidade('KG', 0.5), isNull);
      expect(erroQuantidade('Lt', 1.25), isNull);
      expect(erroQuantidade('UN', 1.5), contains('inteiras'));
      expect(erroQuantidade('Pacote', 2), isNull);
    });
    test('quantidade que arredonda para zero é recusada', () {
      expect(erroQuantidade('KG', 0.0001), isNotNull);
      expect(erroQuantidade('KG', 0), isNotNull);
      expect(erroQuantidade('KG', -1), isNotNull);
      expect(erroQuantidade('KG', 0, aceitaZero: true), isNull);
      expect(erroQuantidade('UN', -1, aceitaZero: true), isNotNull);
    });
    test('validade usa a data de referência', () {
      expect(situacaoValidade('2026-11-02', '2026-11-03', 3)!.vencido, isTrue);
      expect(situacaoValidade('2026-11-03', '2026-11-03', 3)!.texto, 'Vence hoje');
      expect(situacaoValidade('2026-11-06', '2026-11-03', 3)!.alerta, isTrue);
      expect(situacaoValidade('2026-11-07', '2026-11-03', 3)!.alerta, isFalse);
      expect(situacaoValidade('', '2026-11-03', 3), isNull);
    });
    test('servidor: HTTP só na rede local', () {
      expect(validarServidor('192.168.0.10:3000'), 'http://192.168.0.10:3000');
      expect(validarServidor('http://10.0.2.2:3000/'), 'http://10.0.2.2:3000');
      expect(validarServidor('http://padaria.local:3000'), 'http://padaria.local:3000');
      expect(validarServidor('https://gestfast.exemplo.com'), 'https://gestfast.exemplo.com');
      expect(() => validarServidor('http://gestfast.exemplo.com'), throwsFormatException);
      expect(() => validarServidor('http://8.8.8.8'), throwsFormatException);
      expect(() => validarServidor('http://172.32.0.1'), throwsFormatException);
      expect(() => validarServidor(''), throwsFormatException);
      expect(() => validarServidor('ftp://192.168.0.1'), throwsFormatException);
    });
  });

  group('carrinho', () {
    final pao = Produto.deJson(produtoJson(1, 'Pão', unidade: 'KG', estoque: 2, venda: 16.9));
    final bala = Produto.deJson(produtoJson(2, 'Bala', estoque: 3, venda: 0.3));

    test('soma o mesmo produto e respeita o estoque disponível', () {
      final c = Carrinho();
      expect(c.adicionar(pao, 1.5), isNull);
      expect(c.adicionar(pao, 0.5), isNull);
      expect(c.itens, hasLength(1));
      expect(c.itens.first.qtd, 2);
      expect(c.disponivel(pao), 0);
      expect(c.adicionar(pao, 0.1), contains('indisponível'));
    });
    test('recusa fração em produto por unidade', () {
      expect(Carrinho().adicionar(bala, 1.5), contains('inteiras'));
    });
    test('totais com desconto em valor e percentual, sem erro de arredondamento', () {
      final c = Carrinho()..adicionar(bala, 3);
      expect(c.totais(tipoDesconto: 'valor', desconto: 0).total, 0.9);
      expect(c.totais(tipoDesconto: 'percentual', desconto: 10).desconto, 0.09);
      expect(c.totais(tipoDesconto: 'valor', desconto: 0.1).total, 0.8);
    });
    test('limite de desconto vale para todos, menos o Administrador', () {
      final c = Carrinho()..adicionar(pao, 1);
      expect(c.erroDesconto(tipoDesconto: 'percentual', desconto: 30, limitePercent: 20, admin: false), contains('limite'));
      expect(c.erroDesconto(tipoDesconto: 'percentual', desconto: 30, limitePercent: 20, admin: true), isNull);
      expect(c.erroDesconto(tipoDesconto: 'percentual', desconto: 101, limitePercent: 20, admin: true), isNotNull);
      expect(c.erroDesconto(tipoDesconto: 'valor', desconto: 100, limitePercent: 20, admin: true), contains('subtotal'));
      expect(c.erroDesconto(tipoDesconto: 'valor', desconto: -1, limitePercent: 20, admin: true), contains('negativo'));
    });
    test('troco', () {
      final c = Carrinho();
      expect(c.troco(null, 10), isNull);
      expect(c.troco(20, 16.9), 3.1);
      expect(c.troco(10, 16.9), lessThan(0));
    });
    test('busca: código exato primeiro; depois parte do nome, sem acento', () {
      final lista = [pao, bala, Produto.deJson(produtoJson(11, 'Pão de Queijo'))];
      expect(Carrinho.buscar(lista, '7891').map((p) => p.id), [1]);
      expect(Carrinho.buscar(lista, 'pao').map((p) => p.id), [1, 11]);
      expect(Carrinho.buscar(lista, 'xyz'), isEmpty);
      expect(Carrinho.buscar(lista, '  '), isEmpty);
    });
  });
}
