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

  // ✔ desenhado com ícone: o caractere não existe na fonte embutida da web.
  Widget _marca(String v) => v == '✔' ? Icon(Icons.check, size: 17, color: Cores.texto) : const Text('-');

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    Widget linha(String? r, String t) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text.rich(TextSpan(style: TextStyle(fontSize: 14.4, color: Cores.texto), children: [if (r != null) TextSpan(text: '$r ', style: const TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: t)])),
        );
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
              colunas: [
                Coluna('Área', (p) => Text(p.$1), flex: 5),
                Coluna('Administrador', (p) => _marca(p.$2)),
                Coluna('BackOffice', (p) => _marca(p.$3)),
                Coluna('Funcionário', (p) => _marca(p.$4)),
              ],
            ),
            Padding(padding: const EdgeInsets.only(top: 6, bottom: 4), child: Text('* O cancelamento de uma venda exige e-mail e senha de um Administrador ou BackOffice.', style: TextStyle(fontSize: 14.1, color: Cores.texto))),
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
