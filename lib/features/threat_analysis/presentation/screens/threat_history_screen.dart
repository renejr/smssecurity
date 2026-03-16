import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smssecurity/features/threat_analysis/presentation/providers/threat_provider.dart';
import 'package:smssecurity/features/settings/presentation/controllers/trial_controller.dart';
import 'package:smssecurity/features/settings/presentation/widgets/paywall_bottom_sheet.dart';

class ThreatHistoryScreen extends StatefulWidget {
  const ThreatHistoryScreen({super.key});

  @override
  State<ThreatHistoryScreen> createState() => _ThreatHistoryScreenState();
}

class _ThreatHistoryScreenState extends State<ThreatHistoryScreen> {
  String _searchQuery = '';
  bool _isAscending = false; // Padrão: Descendente (mais recentes primeiro)
  final TextEditingController _searchController = TextEditingController();
  
  // Estado para Seleção Múltipla
  final Set<int> _selectedIds = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    // Carrega o histórico ao abrir a tela
    Future.microtask(() => 
      Provider.of<ThreatProvider>(context, listen: false).loadHistory()
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedIds.add(id);
        _isSelectionMode = true;
      }
    });
  }

  void _cancelSelection() {
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });
  }

  void _selectAll(List<dynamic> history) {
    setState(() {
      for (final item in history) {
        _selectedIds.add(item['id'] as int);
      }
      _isSelectionMode = true;
    });
  }

  Future<void> _confirmDeletion(BuildContext context) async {
    final provider = context.read<ThreatProvider>();
    final count = _selectedIds.length;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Apagar $count ${count > 1 ? 'itens' : 'item'}?"),
        content: const Text("Esta ação não pode ser desfeita e os registros serão removidos permanentemente."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text("Apagar", style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (result == true) {
      await provider.deleteHistoryItems(_selectedIds.toList());
      _cancelSelection();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$count ${count > 1 ? 'itens removidos' : 'item removido'}.")),
        );
      }
    }
  }

  List<dynamic> _filterAndSortHistory(List<dynamic> history) {
    List<dynamic> filtered = history;

    // 1. Filtro de Busca
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = history.where((item) {
        final sender = (item['sender'] ?? '').toString().toLowerCase();
        final body = (item['body'] ?? '').toString().toLowerCase();
        return sender.contains(query) || body.contains(query);
      }).toList();
    }

    // 2. Ordenação
    filtered.sort((a, b) {
      final timestampA = a['timestamp'] as int;
      final timestampB = b['timestamp'] as int;
      return _isAscending 
          ? timestampA.compareTo(timestampB) 
          : timestampB.compareTo(timestampA);
    });

    return filtered;
  }

  Color _getThreatColor(double risk, String category) {
    if (risk > 0.75 || category.toLowerCase().contains('phishing') || category == "Fraude Confirmada") {
      return Colors.red;
    }
    if (risk > 0.50 || category.toLowerCase().contains('spam')) {
      return Colors.orange;
    }
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ThreatProvider>();
    final displayedHistory = _filterAndSortHistory(provider.history);

    return Scaffold(
      appBar: _isSelectionMode 
        ? AppBar(
            backgroundColor: Colors.red.withOpacity(0.2),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: _cancelSelection,
            ),
            title: Text("${_selectedIds.length} selecionados"),
            actions: [
              IconButton(
                icon: const Icon(Icons.select_all),
                tooltip: "Selecionar Todos",
                onPressed: () => _selectAll(displayedHistory),
              ),
              IconButton(
                icon: const Icon(Icons.delete),
                tooltip: "Apagar Selecionados",
                onPressed: () => _confirmDeletion(context),
              ),
            ],
          )
        : AppBar(
            title: const Text("Histórico de Ameaças"),
            actions: [
              IconButton(
                icon: Icon(_isAscending ? Icons.arrow_upward : Icons.arrow_downward),
                tooltip: _isAscending ? "Mais antigos primeiro" : "Mais recentes primeiro",
                onPressed: () {
                  setState(() {
                    _isAscending = !_isAscending;
                  });
                },
              ),
            ],
          ),
      body: Column(
        children: [
          // Campo de Busca
          if (!_isSelectionMode)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Buscar por número ou palavra-chave...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty 
                      ? IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.grey.shade900,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
            ),
          
          // Lista de Histórico
          Expanded(
            child: provider.isLoading 
                ? const Center(child: CircularProgressIndicator())
                : displayedHistory.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off, size: 64, color: Colors.grey.shade700),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty 
                                  ? "Nenhum registro no histórico." 
                                  : "Nenhum resultado encontrado.",
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: displayedHistory.length,
                        itemBuilder: (context, index) {
                          final item = displayedHistory[index];
                          final int id = item['id'] as int;
                          final bool isSelected = _selectedIds.contains(id);
                          final bool isBlocked = item['isBlocked'] == true;
                          final double risk = item['riskScore'] as double;
                          final String category = item['category'] ?? 'Desconhecido';
                          final DateTime date = DateTime.fromMillisecondsSinceEpoch(item['timestamp'] as int);
                          final Color riskColor = _getThreatColor(risk, category);
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: isSelected 
                                ? const BorderSide(color: Colors.red, width: 2)
                                : BorderSide.none,
                            ),
                            color: isSelected ? Colors.red.withOpacity(0.1) : null,
                            child: ListTile(
                              leading: Stack(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: riskColor,
                                    child: Icon(
                                      isBlocked ? Icons.block : Icons.check_circle,
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (isSelected)
                                    const Positioned(
                                      right: -2,
                                      bottom: -2,
                                      child: CircleAvatar(
                                        radius: 10,
                                        backgroundColor: Colors.white,
                                        child: Icon(Icons.check, size: 14, color: Colors.red),
                                      ),
                                    ),
                                ],
                              ),
                              title: Text(item['sender'] ?? 'Desconhecido'),
                              subtitle: Consumer<TrialController>(
                                builder: (context, trialController, _) {
                                  final isPremium = trialController.isPremium;
                                  final isTrialExpired = (!isPremium && trialController.daysRemaining <= 0) || trialController.isForceExpired;
                                  
                                  if (isTrialExpired) {
                                    return Stack(
                                      children: [
                                        ImageFiltered(
                                          imageFilter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item['body'] ?? 'Mensagem Oculta', 
                                                maxLines: 2, 
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                "Protegido • Categoria Oculta",
                                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: riskColor),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Positioned(
                                          right: 0,
                                          bottom: 0,
                                          child: Icon(Icons.lock, size: 16, color: riskColor.withOpacity(0.7)),
                                        ),
                                      ],
                                    );
                                  }

                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['body'] ?? '', 
                                        maxLines: 2, 
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "${date.day}/${date.month} ${date.hour}:${date.minute} • $category",
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: riskColor),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              trailing: Text(
                                "${(risk * 100).toStringAsFixed(0)}%",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: riskColor,
                                ),
                              ),
                              onTap: () {
                                if (_isSelectionMode) {
                                  _toggleSelection(id);
                                } else {
                                  _showDetails(context, item, risk);
                                }
                              },
                              onLongPress: () => _toggleSelection(id),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  void _showDetails(BuildContext context, dynamic item, double risk) {
    showDialog(
      context: context,
      builder: (ctx) {
        // Envolve o conteúdo do Dialog em um Consumer para garantir reatividade
        // quando o switch de debug for alternado na SettingsScreen
        return Consumer<TrialController>(
          builder: (context, trialController, _) {
            final isPremium = trialController.isPremium;
            final isTrialExpired = (!isPremium && trialController.daysRemaining <= 0) || trialController.isForceExpired;

            return AlertDialog(
              title: const Text("Detalhes do SMS"),
              content: isTrialExpired 
                ? _buildPaywallContent(context, item)
                : _buildPremiumContent(context, item, risk),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Fechar"),
                )
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPremiumContent(BuildContext context, dynamic item, double risk) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item['body'] ?? ''),
          const SizedBox(height: 16),
          const Text("Análise de Risco:", style: TextStyle(fontWeight: FontWeight.bold)),
          Text("Score: ${(risk * 100).toStringAsFixed(0)}%"),
          Text("Categoria: ${item['category'] ?? 'Desconhecido'}"),
          const SizedBox(height: 16),
          const Text("Ações:", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          // Botão Confirmar Fraude
          if (risk < 0.8) // Só mostra se ainda não for confirmado como alto risco
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              icon: const Icon(Icons.warning, color: Colors.white),
              label: const Text("Confirmar Fraude", style: TextStyle(color: Colors.white)),
              onPressed: () {
                 final provider = context.read<ThreatProvider>();
                 provider.confirmFraud(
                    item['id'] as int,
                    item['sender'] ?? '',
                    item['body'] ?? '',
                    item['category'] ?? 'Desconhecido'
                 );
                 Navigator.pop(context);
                 ScaffoldMessenger.of(context).showSnackBar(
                   const SnackBar(content: Text("Fraude confirmada e reportada!")),
                 );
              },
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.share),
            label: const Text("Compartilhar Alerta"),
            onPressed: () {
              Share.share(
                "🛡️ *ALERTA DE SEGURANÇA - Escudo SMS* 🛡️\n\n"
                "Cuidado com mensagens deste tipo:\n"
                "📩 *${item['body']}*\n\n"
                "🛑 Risco: ${(risk * 100).toStringAsFixed(0)}% (${item['category']})\n"
                "Proteja-se com o Escudo SMS!"
              );
            },
          )
        ],
      ),
    );
  }

  Widget _buildPaywallContent(BuildContext context, dynamic item) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Fundo Desfocado (Conteúdo censurado)
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item['body'] ?? 'Mensagem de exemplo para o blur', style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              const Text("Análise de Risco: Oculto", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              const Text("Score: --%", style: TextStyle(color: Colors.grey)),
              const Text("Categoria: --", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 50), // Espaço para o cadeado
            ],
          ),
        ),
        
        // Cadeado e CTA
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock, size: 48, color: Colors.amber),
              const SizedBox(height: 12),
              const Text(
                "Período de Testes Encerrado",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                "Para ler a mensagem e ver os detalhes da análise, desbloqueie a versão Premium.",
                style: TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  Navigator.pop(context); // Fecha o modal
                  
                  // Abre o Paywall Bottom Sheet
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    builder: (ctx) => const PaywallBottomSheet(),
                  );
                },
                child: const Text("Desbloquear Premium"),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
