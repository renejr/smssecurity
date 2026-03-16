import 'dart:math';
import 'dart:typed_data';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// Serviço de Banco de Dados Vetorial Local usando sqlite3.
/// Implementa uma estratégia de RAG nativo onde os embeddings são armazenados
/// como BLOBs e a busca por similaridade é feita via cálculo de cosseno em memória.
class VectorDbService {
  static final VectorDbService _instance = VectorDbService._internal();
  late final Database _db;
  bool _isInitialized = false;

  factory VectorDbService() {
    return _instance;
  }

  VectorDbService._internal();

  Future<void> init({String? customPath}) async {
    if (_isInitialized) return;

    String dbPath;
    if (customPath != null) {
      dbPath = customPath;
    } else {
      final docDir = await getApplicationDocumentsDirectory();
      dbPath = join(docDir.path, 'sms_shield_rag.db');
    }

    // Abre o banco de dados
    _db = sqlite3.open(dbPath);

    // Cria a tabela de ameaças com suporte a embeddings
    _db.execute('''
      CREATE TABLE IF NOT EXISTS threats (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        text TEXT NOT NULL,
        category TEXT NOT NULL,
        embedding BLOB NOT NULL,
        metadata TEXT
      );
    ''');
    
    // Cria tabela de histórico de SMS analisados
    _db.execute('''
      CREATE TABLE IF NOT EXISTS sms_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sender TEXT NOT NULL,
        body TEXT NOT NULL,
        risk_score REAL NOT NULL,
        category TEXT NOT NULL,
        is_blocked INTEGER DEFAULT 0,
        source TEXT DEFAULT 'local', 
        device_id TEXT,
        timestamp INTEGER NOT NULL
      );
    ''');
    
    // MIGRAÇÃO MANUAL: Verifica se a coluna 'source' existe e adiciona se faltar
    try {
      _db.select('SELECT source FROM sms_history LIMIT 1');
    } catch (_) {
      print("⚠️ Coluna 'source' não encontrada em sms_history. Executando migração...");
      _db.execute("ALTER TABLE sms_history ADD COLUMN source TEXT DEFAULT 'local'");
    }

    // MIGRAÇÃO MANUAL: Verifica se a coluna 'device_id' existe e adiciona se faltar
    try {
      _db.select('SELECT device_id FROM sms_history LIMIT 1');
    } catch (_) {
      print("⚠️ Coluna 'device_id' não encontrada em sms_history. Executando migração...");
      _db.execute("ALTER TABLE sms_history ADD COLUMN device_id TEXT");
    }

    // Cria tabela de cache para verificações de URL externas
    _db.execute('''
      CREATE TABLE IF NOT EXISTS url_cache (
        url TEXT PRIMARY KEY,
        is_malicious INTEGER NOT NULL,
        timestamp INTEGER NOT NULL
      );
    ''');
    
    // Cria tabela de cache para Iscas (Reclame Aqui/Google Search)
    _db.execute('''
      CREATE TABLE IF NOT EXISTS bait_cache (
        bait TEXT PRIMARY KEY,
        complaint_count INTEGER NOT NULL,
        timestamp INTEGER NOT NULL
      );
    ''');

    // Cria tabela de Remetentes Confiáveis (Whitelist do Usuário)
    _db.execute('''
      CREATE TABLE IF NOT EXISTS user_trusted_senders (
        sender TEXT PRIMARY KEY,
        timestamp INTEGER NOT NULL
      );
    ''');
    
    // Cria índice para busca textual simples também
    _db.execute('CREATE INDEX IF NOT EXISTS idx_threats_category ON threats(category);');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_history_timestamp ON sms_history(timestamp DESC);');

    _isInitialized = true;
    print('Vector DB initialized at $dbPath');
  }

  /// Insere um novo registro no histórico
  void insertHistory(String sender, String body, double riskScore, String category, bool isBlocked, {String source = 'local', String? deviceId}) {
    final stmt = _db.prepare('INSERT INTO sms_history (sender, body, risk_score, category, is_blocked, source, device_id, timestamp) VALUES (?, ?, ?, ?, ?, ?, ?, ?)');
    stmt.execute([sender, body, riskScore, category, isBlocked ? 1 : 0, source, deviceId, DateTime.now().millisecondsSinceEpoch]);
    stmt.dispose();
  }

  /// Atualiza o Risk Score de um item do histórico (Confirmação Manual)
  void updateRiskScore(int id, double newScore) {
    try {
      final stmt = _db.prepare('UPDATE sms_history SET risk_score = ?, is_blocked = 1, category = CASE WHEN category = "Desconhecido" THEN "Fraude Confirmada" ELSE category END WHERE id = ?');
      stmt.execute([newScore, id]);
      stmt.dispose();
      print("✅ Risk Score atualizado para $newScore no ID $id");
    } catch (e) {
      print("Erro ao atualizar Risk Score: $e");
    }
  }

  /// Limpa o histórico
  void clearHistory() {
    _db.execute('DELETE FROM sms_history');
  }

  /// Recupera o histórico de SMS com filtro opcional de datas
  List<Map<String, dynamic>> getHistory({int limit = 50, DateTime? startDate, DateTime? endDate}) {
    String query = 'SELECT * FROM sms_history';
    List<dynamic> args = [];
    
    if (startDate != null && endDate != null) {
      query += ' WHERE timestamp >= ? AND timestamp <= ?';
      args.add(startDate.millisecondsSinceEpoch);
      args.add(endDate.millisecondsSinceEpoch);
    }
    
    query += ' ORDER BY timestamp DESC LIMIT ?';
    args.add(limit);
    
    final resultSet = _db.select(query, args);
    
    return resultSet.map((row) => {
      'id': row['id'],
      'sender': row['sender'],
      'body': row['body'],
      'riskScore': row['risk_score'],
      'category': row['category'],
      'isBlocked': row['is_blocked'] == 1,
      'source': row['source'] ?? 'local',
      'deviceId': row['device_id'],
      'timestamp': row['timestamp'],
    }).toList();
  }
  
  /// Salva o cache de verificação de URL
  void cacheUrlCheck(String url, bool isMalicious) {
    // 24 horas de validade (exemplo)
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('INSERT OR REPLACE INTO url_cache (url, is_malicious, timestamp) VALUES (?, ?, ?)');
    stmt.execute([url, isMalicious ? 1 : 0, timestamp]);
    stmt.dispose();
  }

  /// Verifica cache de Isca (Reclame Aqui)
  /// Retorna o número de denúncias ou null se não estiver em cache
  int? checkBaitCache(String bait) {
    // Limpeza de cache antigo (opcional, pode ser feito periodicamente)
    // _db.execute('DELETE FROM bait_cache WHERE timestamp < ?', [DateTime.now().subtract(Duration(days: 7)).millisecondsSinceEpoch]);

    final stmt = _db.prepare('SELECT complaint_count FROM bait_cache WHERE bait = ?');
    final result = stmt.select([bait]);
    
    if (result.isNotEmpty) {
      final count = result.first['complaint_count'] as int;
      print("📦 Cache hit para Isca '$bait': $count reclamações");
      return count;
    }
    return null;
  }

  /// Salva o cache de Isca (Reclame Aqui)
  void cacheBaitCheck(String bait, int complaintCount) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('INSERT OR REPLACE INTO bait_cache (bait, complaint_count, timestamp) VALUES (?, ?, ?)');
    stmt.execute([bait, complaintCount, timestamp]);
    stmt.dispose();
  }

  /// Adiciona um remetente à Whitelist (Confiáveis)
  void addToWhitelist(String sender) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('INSERT OR REPLACE INTO user_trusted_senders (sender, timestamp) VALUES (?, ?)');
    stmt.execute([sender, timestamp]);
    stmt.dispose();
    print("✅ Remetente '$sender' adicionado à Whitelist.");
  }

  /// Verifica se o remetente está na Whitelist
  bool isWhitelisted(String sender) {
    final result = _db.select('SELECT 1 FROM user_trusted_senders WHERE sender = ?', [sender]);
    return result.isNotEmpty;
  }

  /// Remove um SMS do histórico (ex: falso positivo)
  void deleteFromHistory(String sender, String body) {
    // Tenta remover pela combinação exata ou pelo remetente recente
    // Como não temos ID fácil na UI às vezes, removemos o mais recente desse sender com esse body
    final stmt = _db.prepare('DELETE FROM sms_history WHERE sender = ? AND body = ?');
    stmt.execute([sender, body]);
    stmt.dispose();
    print("🗑️ SMS de '$sender' removido do histórico.");
  }

  /// Remove múltiplos alertas do histórico por ID
  void deleteAlertsByIds(List<int> ids) {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    final stmt = _db.prepare('DELETE FROM sms_history WHERE id IN ($placeholders)');
    stmt.execute(ids);
    stmt.dispose();
    print("🗑️ ${ids.length} alertas removidos do histórico.");
  }
  
  /// Verifica se URL está no cache (retorna null se não estiver)
  bool? checkUrlCache(String url) {
    final resultSet = _db.select('SELECT is_malicious FROM url_cache WHERE url = ?', [url]);
    if (resultSet.isNotEmpty) {
       return resultSet.first['is_malicious'] == 1;
    }
    return null;
  }
  void insertThreat(String text, String category, List<double> embedding, {String? metadata}) {
    final stmt = _db.prepare('INSERT INTO threats (text, category, embedding, metadata) VALUES (?, ?, ?, ?)');
    final blob = _encodeEmbedding(embedding);
    stmt.execute([text, category, blob, metadata]);
    stmt.dispose();
  }

  /// Busca as N ameaças mais similares ao embedding fornecido.
  /// Retorna uma lista de mapas contendo o texto, categoria e score de similaridade.
  Future<List<Map<String, dynamic>>> searchSimilarThreats(List<double> queryEmbedding, {int limit = 5}) async {
    final resultSet = _db.select('SELECT id, text, category, embedding FROM threats');
    
    final results = <Map<String, dynamic>>[];

    for (final row in resultSet) {
      final id = row['id'] as int;
      final text = row['text'] as String;
      final category = row['category'] as String;
      final embeddingBlob = row['embedding'] as List<int>; // sqlite3 retorna BLOB como List<int>
      
      final embedding = _decodeEmbedding(Uint8List.fromList(embeddingBlob));
      final similarity = _cosineSimilarity(queryEmbedding, embedding);

      results.add({
        'id': id,
        'text': text,
        'category': category,
        'similarity': similarity,
      });
    }

    // Ordena por similaridade decrescente
    results.sort((a, b) => (b['similarity'] as double).compareTo(a['similarity'] as double));

    return results.take(limit).toList();
  }

  /// Busca ameaças baseada em palavras-chave (Fallback quando o modelo de embeddings falha).
  /// Aplica pesos heurísticos para termos de alta periculosidade.
  Future<List<Map<String, dynamic>>> searchByKeywords(String query, {int limit = 5}) async {
    final cleanQuery = query.toLowerCase();
    
    // Lista de termos de alto risco e seus pesos
    final highRiskTerms = {
      'pix': 0.9, 'bloqueio': 0.85, 'bloqueada': 0.85, 'bloqueado': 0.85,
      'fraude': 0.9, 'senha': 0.8, 'acesso': 0.6, 'segurança': 0.6,
      'atualize': 0.7, 'clique': 0.6, 'link': 0.6, 'urgente': 0.7,
      'expira': 0.6, 'cancelamento': 0.6, 'taxa': 0.7, 'alfandega': 0.7,
      'correios': 0.5, 'caixa': 0.5, 'nubank': 0.5, 'bb': 0.5, 'santander': 0.5
    };

    // Calcula um score base heurístico apenas pela presença de palavras-chave na query
    double heuristicScore = 0.0;
    int matches = 0;
    
    for (final term in highRiskTerms.keys) {
      if (cleanQuery.contains(term)) {
        heuristicScore = max(heuristicScore, highRiskTerms[term]!);
        matches++;
      }
    }
    
    // Se tiver muitos matches, aumenta a confiança
    if (matches > 2) heuristicScore = min(0.95, heuristicScore + 0.1);

    // Busca no banco por texto similar para encontrar a categoria mais provável
    final keywords = cleanQuery.split(' ').where((w) => w.length > 3).toList();
    if (keywords.isEmpty) return [];

    // Monta query dinâmica (OR)
    final whereClause = keywords.map((_) => 'text LIKE ?').join(' OR ');
    final args = keywords.map((w) => '%$w%').toList();
    
    final resultSet = _db.select('SELECT id, text, category FROM threats WHERE $whereClause LIMIT ?', [...args, limit]);

    // Se não achou nada no banco, mas tem score heurístico alto, cria um alerta genérico
    if (resultSet.isEmpty && heuristicScore > 0.6) {
      return [{
        'id': -1,
        'text': 'Padrão suspeito detectado por palavras-chave.',
        'category': 'Suspeita de Fraude',
        'similarity': heuristicScore,
      }];
    }

    return resultSet.map((row) {
      // Combina o score heurístico da query com o fato de ter achado algo no banco
      // Se achou no banco, é muito provável que seja o golpe cadastrado.
      double combinedScore = max(0.6, heuristicScore); 
      
      return {
        'id': row['id'],
        'text': row['text'],
        'category': row['category'],
        'similarity': combinedScore,
      };
    }).toList();
  }

  /// Converte List<double> para Uint8List (BLOB)
  Uint8List _encodeEmbedding(List<double> vector) {
    final buffer = Float64List.fromList(vector).buffer;
    return buffer.asUint8List();
  }

  /// Converte Uint8List (BLOB) para List<double>
  List<double> _decodeEmbedding(Uint8List bytes) {
    final buffer = bytes.buffer;
    return Float64List.view(buffer).toList();
  }

  /// Calcula a similaridade de cosseno entre dois vetores
  double _cosineSimilarity(List<double> v1, List<double> v2) {
    if (v1.length != v2.length) return 0.0;

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < v1.length; i++) {
      dotProduct += v1[i] * v2[i];
      normA += v1[i] * v1[i];
      normB += v2[i] * v2[i];
    }

    if (normA == 0 || normB == 0) return 0.0;
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }
  
  void close() {
    _db.dispose();
  }
}
