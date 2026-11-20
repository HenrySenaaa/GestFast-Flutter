// Ajuda: mesmo conteúdo do v1.
import 'package:flutter/material.dart';

import '../core/tema.dart';
import '../widgets/comuns.dart';

class AjudaTela extends StatelessWidget {
  const AjudaTela({super.key});

  static const _perfis = <(String, String, String, String)>[
    ('Painel, estoque, conferência, entradas e saídas', '✔', '✔', '✔'),
    ('Requisições: criar, receber e cancelar', '✔', '✔', '✔'),
    ('Requisições: cotar e gerar AF', '✔', '✔', '-'),
    ('Cadastro de produtos', '✔', '✔', '-'),
    ('Caixa (vendas), edição e cancelamento*', '✔', '-', '✔'),
    ('Relatórios (PDF e Excel)', '✔', '✔', '-'),
    ('Funcionários, configurações e logs', '✔', '-', '-'),
  ];


  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    // <p> sem classe dentro de .ajuda-details-list: 16px e sem margem entre os parágrafos.
    Widget linha(String? r, String t) => Text.rich(TextSpan(style: TextStyle(fontSize: 16, color: Cores.texto), children: [if (r != null) TextSpan(text: '$r ', style: const TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: t)]));
    return Pagina(
      cabecalho: const CabecalhoAba('Ajuda'),
      filhos: [
        Cartao(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const TituloH3('GestFast - Sistema de Gestão de Estoque Ágil para Padarias'),
            linha('Curso:', 'Análise e Desenvolvimento de Sistemas • USCS (Universidade Municipal de São Caetano do Sul)'),
            linha('Projeto:', 'PIM / PE - GestFast'),
            linha('Integrantes:', 'Henry Sena, Nicolas Viana, João Nabeshima, Lucas Nunes e Daniel Farias.'),
            linha('Foco:', 'Solução ágil para conferência e controle de estoque de panificadoras locais de bairro.'),
          ]),
        ),
        Cartao(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const TituloH3('Perfis de acesso'),
            Tabela<(String, String, String, String)>(
              itens: _perfis,
              larguraMinima: 620,
              vazioSimples: true,
              colunas: [
                Coluna('Área', (p) => Text(p.$1), flex: 5),
                Coluna('Administrador', (p) => Text(p.$2)),
                Coluna('BackOffice', (p) => Text(p.$3)),
                Coluna('Funcionário', (p) => Text(p.$4)),
              ],
            ),
            Padding(padding: const EdgeInsets.only(top: 6, bottom: 10), child: Text('* O cancelamento de uma venda exige e-mail e senha de um Administrador ou BackOffice.', style: TextStyle(fontSize: 14.1, color: Cores.texto))),
          ]),
        ),
        Cartao(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const TituloH3('Dicas rápidas'),
            linha(null, '• Use a barra de pesquisa no topo para ir direto a qualquer tela (ex.: digite "venda").'),
            linha(null, '• No caixa, digite ou leia o código de barras e pressione Enter para localizar o produto.'),
            linha(null, '• Produtos vendidos por unidade, pacote, dúzia ou fatia só aceitam quantidades inteiras; apenas KG e litro aceitam frações.'),
            linha(null, '• Os botões A-, A+ e ◐ no topo aumentam o texto e ativam o alto contraste.'),
          ]),
        ),
      ],
    );
  }
}
