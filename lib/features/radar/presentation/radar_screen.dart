import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smssecurity/core/services/global_intelligence_service.dart';
import 'package:smssecurity/core/services/admob_service.dart';
import 'package:smssecurity/features/settings/presentation/controllers/trial_controller.dart';

class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key});

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> {
  final GlobalIntelligenceService _service = GlobalIntelligenceService();
  Map<String, dynamic>? _stats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
    
    // Tenta carregar Interstitial ao entrar na tela (se expirado)
    WidgetsBinding.instance.addPostFrameCallback((_) {
       final trial = context.read<TrialController>();
       if ((!trial.isPremium && trial.daysRemaining <= 0) || trial.isForceExpired) {
          AdmobService.loadInterstitial();
       }
    });
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    
    // Gatilho de Interstitial Ad ao Sincronizar/Carregar
    final trial = context.read<TrialController>();
    if ((!trial.isPremium && trial.daysRemaining <= 0) || trial.isForceExpired) {
        print("📺 Radar: Exibindo Interstitial Ad...");
        AdmobService.showInterstitial();
    }

    final stats = await _service.getCommunityStats();
    if (mounted) {
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Radar MDXHQ"),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  if (_stats != null) ...[
                    _buildStatCard(
                      icon: Icons.shield,
                      color: Colors.blue,
                      title: "Vacinas Globais",
                      value: "${_stats!['total_scams']}",
                      subtitle: "Ameaças únicas catalogadas",
                    ),
                    const SizedBox(height: 16),
                    _buildStatCard(
                      icon: Icons.block,
                      color: Colors.red,
                      title: "Golpes Bloqueados",
                      value: "${_stats!['total_blocked']}",
                      subtitle: "Proteções em tempo real",
                    ),
                    const SizedBox(height: 16),
                    _buildStatCard(
                      icon: Icons.people,
                      color: Colors.green,
                      title: "Usuários Ativos",
                      value: "${_stats!['active_users']}",
                      subtitle: "Protegendo a comunidade",
                    ),
                  ] else
                    const Center(
                      child: Text("Não foi possível carregar os dados."),
                    ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _loadStats,
                      icon: const Icon(Icons.sync),
                      label: const Text("Sincronizar Agora"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Sua proteção é atualizada automaticamente a cada nova ameaça detectada pela rede.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const Icon(Icons.public, size: 80, color: Colors.deepPurple),
        const SizedBox(height: 16),
        Text(
          "Inteligência Coletiva",
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Você está conectado à rede global de proteção MDXHQ.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
