// Regras do carrinho do caixa, sem interface. Os mesmos cálculos são refeitos pelo servidor.
import '../core/regras.dart';
import '../models/modelos.dart';

class ItemCarrinho {
  ItemCarrinho(this.idProduto, this.nome, this.unidade, this.preco, this.qtd);
  final int idProduto;
  final String nome, unidade;
  final double preco;
  double qtd;
  double get subtotal => qtd * preco;
}

class Totais {
  const Totais(this.subtotal, this.desconto, this.total);
  final double subtotal, desconto, total;
}

class Carrinho {
  final List<ItemCarrinho> itens = [];

  double noCarrinho(int idProduto) => itens.where((i) => i.idProduto == idProduto).fold(0.0, (a, i) => a + i.qtd);
  double disponivel(Produto p) => r3(p.estoque - noCarrinho(p.id));

  /// Checagens do v1 ao inserir no pedido, na mesma ordem e com as mesmas mensagens. Devolve o erro, ou null.
  String? validar(Produto p, double? q) {
    if (q == null || !(q > 0)) return 'Informe uma quantidade maior que zero.';
    if (!aceitaFracao(p.unidade) && q != q.roundToDouble()) return '${p.nome} é vendido em ${p.unidade}: informe uma quantidade inteira.';
    final disp = disponivel(p);
    if (q > disp) return 'Quantidade indisponível em estoque! Disponível: ${quantidade(disp)} ${p.unidade}.';
    return null;
  }

  /// Inclui o produto (soma se já estiver no carrinho). Devolve a mensagem de erro, ou null.
  String? adicionar(Produto p, double? q) {
    final erro = validar(p, q);
    if (erro != null) return erro;
    final existente = itens.where((i) => i.idProduto == p.id).firstOrNull;
    if (existente != null) {
      existente.qtd = r3(existente.qtd + q!);
    } else {
      itens.add(ItemCarrinho(p.id, p.nome, p.unidade, p.venda, r3(q!)));
    }
    return null;
  }

  Totais totais({required String tipoDesconto, required double desconto}) {
    final sub = r2(itens.fold(0.0, (a, i) => a + i.subtotal));
    final valor = r2(tipoDesconto == 'percentual' ? sub * desconto / 100 : desconto);
    return Totais(sub, valor, r2(sub - valor));
  }

  /// Regras de desconto. Só o Administrador pode passar do limite configurado.
  String? erroDesconto({required String tipoDesconto, required double desconto, required double limitePercent, required bool admin}) {
    if (desconto < 0) return 'O desconto não pode ser negativo.';
    if (tipoDesconto == 'percentual' && desconto > 100) return 'O desconto percentual não pode passar de 100%.';
    final t = totais(tipoDesconto: tipoDesconto, desconto: desconto);
    if (t.desconto > t.subtotal) return 'O desconto não pode ser maior que o subtotal da venda.';
    if (!admin && t.subtotal > 0 && t.desconto / t.subtotal * 100 > limitePercent + 1e-9) {
      return 'Desconto acima do limite permitido (${quantidade(limitePercent)}% do subtotal).';
    }
    return null;
  }

  /// Troco para venda em dinheiro; null se o valor recebido não foi informado.
  double? troco(double? recebido, double total) => recebido == null ? null : r2(recebido - total);

  /// Procura primeiro pelo código exato; depois por parte do nome ou do código (em minúsculas, como no v1).
  static List<Produto> buscar(List<Produto> produtos, String termo) {
    final t = termo.trim().toLowerCase();
    if (t.isEmpty) return const [];
    final exatos = produtos.where((p) => p.codigo.toLowerCase() == t).toList();
    if (exatos.isNotEmpty) return exatos;
    return produtos.where((p) => '${p.nome} ${p.codigo}'.toLowerCase().contains(t)).toList();
  }
}
