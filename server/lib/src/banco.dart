// banco.dart - Pool de conexões MySQL, transações e conversão de valores.
//
// Toda consulta usa prepared statement (protocolo binário). Os valores voltam como o mysql2
// do servidor Node os entregava (com `decimalNumbers` e `dateStrings`):
//   inteiros, DECIMAL e COUNT/SUM -> número (double)
//   DATE -> 'AAAA-MM-DD'      DATETIME -> 'AAAA-MM-DD HH:MM:SS'      texto/ENUM -> String
//
// Os marcadores seguem o mysql2: `IN (?)` com lista vira `IN (?, ?, ?)`, `VALUES ?` com lista
// de listas vira `VALUES (?, ?), (?, ?)` e `SET ?` com mapa vira `` SET `a` = ?, `b` = ? ``.
import 'dart:async';

import 'package:mysql_dart/mysql_dart.dart';

import 'js.dart';

/// Linha de resultado: coluna -> valor, na ordem das colunas.
typedef Registro = Map<String, Object?>;

class Resultado {
  Resultado(this.linhas, this.insertId, this.afetadas);
  final List<Registro> linhas;
  final int insertId;
  final int afetadas;
}

/// Quem executa SQL: o pool (fora de transação) ou uma conexão em transação.
abstract class Executor {
  Future<Resultado> query(String sql, [List<Object?> params = const []]);

  Future<List<Registro>> linhas(String sql, [List<Object?> params = const []]) async => (await query(sql, params)).linhas;
}

// Tipos de coluna do protocolo MySQL.
const _numericos = {0, 1, 2, 3, 4, 5, 8, 9, 13, 246};
const _datas = {10, 14};

/// Valor do parâmetro como o mysql2 o escreveria no SQL.
Object? _parametro(Object? v) {
  if (v == null || v is Undefined) return null;
  if (v is bool) return v ? 1 : 0;
  if (v is int) return v;
  if (v is double) {
    // Inteiro exato vai como inteiro; o resto vai como o texto do JS ("2.5", "1e+21"),
    // que o MySQL converte como o literal que o mysql2 montava.
    if (isInteger(v) && v.abs() <= 9007199254740992) return v.toInt();
    return numStr(v);
  }
  if (v is String) return v;
  return toStr(v);
}

/// Expande `?` com lista/mapa e devolve o SQL final e os parâmetros simples.
(String, List<Object?>) expandirMarcadores(String sql, List<Object?> params) {
  final sb = StringBuffer();
  final saida = <Object?>[];
  var idx = 0;
  String? aspas;
  for (var i = 0; i < sql.length; i++) {
    final ch = sql[i];
    if (aspas != null) {
      sb.write(ch);
      if (ch == aspas) aspas = null;
      continue;
    }
    if (ch == "'" || ch == '"' || ch == '`') {
      aspas = ch;
      sb.write(ch);
      continue;
    }
    if (ch != '?') {
      sb.write(ch);
      continue;
    }
    if (idx >= params.length) {
      sb.write('?');
      continue;
    }
    final p = params[idx++];
    if (p is List) {
      sb.write(
        p.map((e) {
          if (e is List) {
            saida.addAll(e.map(_parametro));
            return '(${List.filled(e.length, '?').join(', ')})';
          }
          saida.add(_parametro(e));
          return '?';
        }).join(', '),
      );
    } else if (p is Map) {
      final partes = <String>[];
      p.forEach((k, v) {
        if (v is Undefined) return;
        partes.add('`${k.toString().replaceAll('`', '``')}` = ?');
        saida.add(_parametro(v));
      });
      sb.write(partes.join(', '));
    } else {
      sb.write('?');
      saida.add(_parametro(p));
    }
  }
  return (sb.toString(), saida);
}

Object? _converter(int tipo, Object? v) {
  if (v == null) return null;
  if (v is! String) return v;
  if (_numericos.contains(tipo)) return double.parse(v);
  if (_datas.contains(tipo)) return v.length > 10 ? v.substring(0, 10) : v;
  return v;
}

Future<Resultado> _executar(MySQLConnection conn, String sql, List<Object?> params) async {
  final (texto, valores) = expandirMarcadores(sql, params);
  final rs = await conn.execute(texto, valores.isEmpty ? null : valores);
  final cols = rs.cols.toList();
  final linhas = <Registro>[];
  for (final r in rs.rows) {
    final m = <String, Object?>{};
    for (var i = 0; i < cols.length; i++) {
      m[cols[i].name] = _converter(cols[i].type.intVal, r.colAt(i));
    }
    linhas.add(m);
  }
  return Resultado(linhas, rs.lastInsertID.toInt(), rs.affectedRows.toInt());
}

/// Conexão emprestada do pool dentro de uma transação.
class Transacao extends Executor {
  Transacao(this._conn);
  final MySQLConnection _conn;

  /// Produtos travados nesta transação (alertas de estoque são refeitos depois do COMMIT).
  final Set<double> produtosTocados = {};

  @override
  Future<Resultado> query(String sql, [List<Object?> params = const []]) => _executar(_conn, sql, params);
}

class Banco extends Executor {
  Banco({
    required String host,
    required int porta,
    required String usuario,
    required String senha,
    required String nome,
    int conexoes = 10,
  }) : _pool = MySQLConnectionPool(
          host: host,
          port: porta,
          userName: usuario,
          password: senha,
          databaseName: nome,
          maxConnections: conexoes,
          // Como o mysql2: sem TLS por padrão e utf8mb4 (emojis e acentos de 4 bytes).
          secure: false,
          allowPublicKeyRetrieval: true,
          collation: 'utf8mb4_unicode_ci',
          autoPreparedStatementCacheCapacity: 256,
        );

  final MySQLConnectionPool _pool;

  @override
  Future<Resultado> query(String sql, [List<Object?> params = const []]) async =>
      await _pool.withConnection((c) => _executar(c, sql, params));

  /// Executa [fn] numa transação: erro = ROLLBACK de tudo.
  Future<T> transacao<T>(Future<T> Function(Transacao c) fn) async {
    return await _pool.withConnection((conn) async {
      final t = Transacao(conn);
      await conn.execute('START TRANSACTION');
      try {
        final r = await fn(t);
        await conn.execute('COMMIT');
        return r;
      } catch (_) {
        await conn.execute('ROLLBACK');
        rethrow;
      }
    });
  }

  Future<void> testarConexao() async {
    await query('SELECT 1');
  }

  Future<void> fechar() => _pool.close();
}
