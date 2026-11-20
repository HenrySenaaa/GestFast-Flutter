// Leitura do JSON da API (modelos) e formatação/regras pt-BR, com os casos de borda do v1.
import 'package:flutter_test/flutter_test.dart';
import 'package:gestfast/core/regras.dart';
import 'package:gestfast/core/rotas.dart';
import 'package:gestfast/features/carrinho.dart';
import 'package:gestfast/models/modelos.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'apoio.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  group('formatação (GF.money, GF.num2, GF.qty, GF.date)', () {
    test('moeda', () {
      expect(dinheiro(0), 'R\$ 0,00');
      expect(dinheiro(null), 'R\$ 0,00');
      expect(dinheiro('12.5'), 'R\$ 12,50');
      expect(dinheiro(1234567.891), 'R\$ 1.234.567,89');
      expect(dinheiro(-5), '-R\$ 5,00');
      expect(dinheiro(0.005), 'R\$ 0,01');
      expect(dinheiro(1234.5).contains(' '), isFalse, reason: 'espaço comum, para comparar textos');
    });
    test('duas casas', () {
      expect(num2(0), '0,00');
      expect(num2(1234.5), '1.234,50');
      expect(num2('3.456'), '3,46');
    });
    test('quantidade com até 3 casas, como o maximumFractionDigits: 3', () {
      expect(quantidade(0), '0');
      expect(quantidade(2.5), '2,5');
      expect(quantidade(0.125), '0,125');
      expect(quantidade(1.0004), '1');
      expect(quantidade(1234), '1.234');
      expect(quantidade(-3), '-3');
      expect(quantidade('7'), '7');
    });
    test('datas no formato do v1', () {
      expect(dataBR(null), '-');
      expect(dataBR('2026-01-05'), '05/01/2026');
      expect(dataBR('2026-01-05 08:09:10'), '05/01/2026 08:09:10');
      expect(dataBR('ontem'), 'ontem', reason: 'texto que não é data fica como está');
      expect(dataISO(DateTime(2026, 2, 3)), '2026-02-03');
      expect(lerDataISO('2026-13-40'), isNotNull, reason: 'só separa as partes; quem valida é o servidor');
      expect(lerDataISO('2026-1'), isNull);
      expect(lerDataISO(null), isNull);
      expect(lerDataISO('aaaa-bb-cc'), isNull);
    });
    test('somar dias usa a data do servidor', () {
      expect(somarDias('2028-02-27', 2), '2028-02-29', reason: 'ano bissexto');
      expect(somarDias('2026-10-31', 4), '2026-11-04');
    });
    test('número digitado', () {
      expect(numero(3), 3);
      expect(numero('2,5'), 2.5);
      expect(numero('x'), 0);
      expect(numero(null), 0);
      expect(lerNumero(' 2 '), 2);
      expect(lerNumero('1 234,5'), 1234.5);
      expect(lerNumero('-1'), -1);
      expect(lerNumero('1e400'), isNull, reason: 'infinito não é número');
    });
    test('arredondamento sem erro de ponto flutuante', () {
      expect(r2(1.005), 1.01);
      expect(r2(0.1 + 0.2), 0.3);
      expect(r3(1.0005), 1.001);
    });
  });

  group('regras', () {
    test('frações: só kg, lt e l, sem diferenciar maiúsculas', () {
      for (final u in ['KG', 'kg', 'Lt', 'LT', 'l', 'L']) {
        expect(aceitaFracao(u), isTrue, reason: u);
      }
      for (final u in ['UN', 'Pacote', 'DZ', 'Fatia', '', null]) {
        expect(aceitaFracao(u), isFalse, reason: '$u');
      }
    });
    test('mensagens de quantidade', () {
      expect(erroQuantidade('UN', null), 'Informe uma quantidade maior que zero.');
      expect(erroQuantidade('UN', 0.5, nome: 'Bala'), 'Bala é controlado em UN e só aceita quantidades inteiras.');
      expect(erroQuantidade('UN', -1, aceitaZero: true), 'Informe zero ou mais.');
      expect(erroQuantidade(null, 1.5), 'Este produto é controlado em UN e só aceita quantidades inteiras.');
    });
    test('textos da validade iguais ao GF.validade', () {
      expect(situacaoValidade('2026-11-01', '2026-11-03', 3)!.texto, 'Vencido há 2 dia(s)');
      expect(situacaoValidade('2026-11-05', '2026-11-03', 3)!.texto, 'Vence em 2 dia(s)');
      expect(situacaoValidade('2026-11-05', '2026-11-03', 1)!.alerta, isFalse, reason: 'aviso configurado em 1 dia');
      expect(situacaoValidade('2026-11-05', null, 3), isNull);
      expect(situacaoValidade('2026-11-03', '2026-11-03', 0)!.alerta, isTrue);
    });
    test('listas na mesma ordem dos <select> do v1', () {
      expect(unidades, ['UN', 'KG', 'Pacote', 'DZ', 'Fatia', 'Lt']);
      expect(formasPagamento, ['Dinheiro', 'Cartão Débito', 'Cartão Crédito', 'PIX']);
      expect(motivosPerda, ['Vencido', 'Quebra/Avaria', 'Sobra do dia', 'Outro']);
      expect(situacoesAbertas, ['Em Aberto', 'Cotado', 'AF Gerada']);
    });
    test('perfis e acentos', () {
      expect(nomePerfil('Funcionario'), 'Funcionário');
      expect(nomePerfil('BackOffice'), 'BackOffice');
      expect(nomePerfil(null), '-');
      expect(semAcento('Pão de Açúcar ÉÇ'), 'pao de acucar ec');
    });
    test('rede local', () {
      expect(hostLocal('LOCALHOST'), isTrue);
      expect(hostLocal('::1'), isTrue);
      expect(hostLocal('169.254.1.1'), isTrue);
      expect(hostLocal('172.16.0.1'), isTrue);
      expect(hostLocal('172.15.0.1'), isFalse);
      expect(hostLocal('192.169.0.1'), isFalse);
      expect(hostLocal('10.0.0.300'), isFalse);
      expect(validarServidor('http://[::1]:3000'), 'http://[::1]:3000');
      expect(validarServidor('localhost'), 'http://localhost');
    });
  });

  group('menu e busca: mesmos nomes, emojis e permissões do v1', () {
    test('ordem do menu lateral', () {
      expect(destinos.map((d) => d.rotulo), ['Início', 'Verificar Estoque', 'Requisição', 'Cadastro de Produtos', 'Saída de Produtos', 'Entrada de Produtos', 'Venda', 'Histórico de Vendas', 'Relatórios', 'Funcionários', 'Configuração', 'Ajuda']);
      expect(destinos.map((d) => d.perm), ['dashboard:ver', 'estoque:conferir', 'requisicoes:ver', 'produtos:editar', 'movimentos:ver', 'movimentos:ver', 'vendas:vender', 'vendas:ver', 'relatorios:ver', 'usuarios:gerir', null, null]);
    });
    test('busca usa os rótulos e emojis de OPCOES', () {
      expect(destinos.map((d) => '${d.emoji} ${d.rotuloBusca}'), ['🏠 Início (Dashboard)', '📦 Verificar Estoque', '📝 Requisições de Compra', '🏷️ Cadastro de Produtos', '📤 Saída de Produtos', '📥 Entrada de Produtos', '🛒 Venda (Caixa)', '🧾 Histórico de Vendas', '📊 Relatórios', '👥 Funcionários', '⚙️ Configuração', '❓ Ajuda']);
    });
  });

  group('modelos', () {
    test('usuário: números como texto, perfis', () {
      final u = Usuario.deJson({'id_usuario': '7', 'nome': 'Ana', 'email': 'a@x.com', 'cargo': null, 'perfil': 'BackOffice', 'id_perfil': 2, 'status': 'Ativo'});
      expect([u.id, u.cargo, u.gerente, u.admin, u.ativo], [7, '', true, false, true]);
      expect(Usuario.deJson({'perfil': 'Funcionario', 'status': 'Inativo'}).gerente, isFalse);
    });

    test('produto: preços em texto (DECIMAL do MySQL) e campos nulos', () {
      final p = Produto.deJson({...produtoJson(3, 'Queijo', unidade: 'KG'), 'preco_venda': '39.90', 'quantidade_estoque': '1.250', 'estoque_minimo': 2, 'lote': null, 'validade': null, 'imagem': null});
      expect([p.venda, p.estoque, p.lote, p.validade, p.imagem], [39.9, 1.25, '', '', '']);
      expect(p.critico, isTrue, reason: 'estoque <= mínimo, como o v1');
      expect(Produto.deJson({...produtoJson(4, 'X'), 'quantidade_estoque': 1, 'estoque_minimo': 1}).critico, isTrue);
      expect(Produto.deJson({...produtoJson(4, 'X'), 'status': 'Inativo'}).ativo, isFalse);
    });

    test('movimentação mantém o texto original da observação', () {
      final m = Movimentacao.deJson({'id_movimentacao': 1, 'tipo_movimentacao': 'Saída', 'quantidade': '2', 'observacao': 'Ajuste da conferência #3 (sistema 5 → físico 3)', 'origem': 'perda', 'motivo_perda': 'Vencido', 'valor_total': '4.5'});
      expect(m.observacao, 'Ajuste da conferência #3 (sistema 5 → físico 3)');
      expect([m.quantidade, m.valorTotal, m.origem, m.motivoPerda], [2, 4.5, 'perda', 'Vencido']);
    });

    test('venda: recebido e troco opcionais, itens', () {
      final v = Venda.deJson({'id_venda': 1, 'codigo_venda': 'VENDA-1', 'valor_total': 10, 'status_venda': 'Concluída', 'valor_recebido': null, 'troco': null, 'itens': [{'id_item_venda': 5, 'id_produto': 2, 'nome_produto': 'Pão', 'quantidade': '3', 'valor_unitario': '1.5', 'subtotal': 4.5}, 'lixo']});
      expect([v.recebido, v.troco, v.concluida, v.itens.length, v.itens.first.quantidade], [null, null, true, 1, 3]);
      expect(Venda.deJson({'status_venda': 'Cancelada'}).concluida, isFalse);
    });

    test('requisição: pendente arredondado, produto fora do catálogo e situações abertas', () {
      final r = Requisicao.deJson({'id_requisicao': 1, 'id_produto': null, 'quantidade_pedida': 1.3, 'quantidade_atendida': 1.1, 'situacao': 'AF Gerada', 'historico': [{'situacao': 'Em Aberto'}]});
      expect([r.idProduto, r.pendente, r.aberta, r.historico.length], [null, 0.2, true, 1]);
      for (final s in ['Finalizado', 'Cancelado']) {
        expect(Requisicao.deJson({'situacao': s}).aberta, isFalse);
      }
    });

    test('configurações: simulações só com booleano verdadeiro (bug 19)', () {
      final c = Configuracoes.deJson({'estabelecimento': 'P', 'descontoMaximoPercent': '12.5', 'intervaloAtualizacaoSeg': '5', 'diasAlertaValidade': 2, 'simularCartaoNegado': 'false', 'simularFornecedorIndisponivel': true});
      expect([c.descontoMaximo, c.intervaloSeg, c.diasValidade, c.simularCartao, c.simularFornecedor], [12.5, 5, 2, false, true]);
    });

    test('listaJson ignora o que não é objeto', () {
      expect(listaJson([{'a': 1}, 2, null, 'x', {'b': 2}]), [{'a': 1}, {'b': 2}]);
      expect(listaJson(null), isEmpty);
      expect(listaJson({'a': 1}), isEmpty);
    });
  });

  group('carrinho: regras do v1', () {
    final kg = Produto.deJson(produtoJson(1, 'Queijo', unidade: 'KG', estoque: 1.5, venda: 40));
    test('fração em kg e limite do disponível com 3 casas', () {
      final c = Carrinho();
      expect(c.adicionar(kg, 0.75), isNull);
      expect(c.adicionar(kg, 0.751), 'Quantidade indisponível em estoque! Disponível: 0,75 KG.');
      expect(c.adicionar(kg, 0.75), isNull);
      expect(c.disponivel(kg), 0);
      expect(c.totais(tipoDesconto: 'valor', desconto: 0).subtotal, 60);
    });
    test('mensagem do limite de desconto com o percentual configurado', () {
      final c = Carrinho()..adicionar(kg, 1);
      expect(c.erroDesconto(tipoDesconto: 'valor', desconto: 10, limitePercent: 12.5, admin: false), 'Desconto acima do limite permitido (12,5% do subtotal).');
      expect(c.erroDesconto(tipoDesconto: 'valor', desconto: 5, limitePercent: 12.5, admin: false), isNull, reason: '12,5% exatos');
      expect(c.erroDesconto(tipoDesconto: 'percentual', desconto: 100, limitePercent: 0, admin: true), isNull);
    });
    test('carrinho vazio não tem limite', () {
      expect(Carrinho().erroDesconto(tipoDesconto: 'valor', desconto: 0, limitePercent: 0, admin: false), isNull);
    });
  });
}
