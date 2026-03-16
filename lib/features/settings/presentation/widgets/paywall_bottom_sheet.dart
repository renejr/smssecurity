import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:provider/provider.dart';
import 'package:smssecurity/core/services/payment_service.dart';
import 'package:smssecurity/features/settings/presentation/controllers/trial_controller.dart';

class PaywallBottomSheet extends StatefulWidget {
  const PaywallBottomSheet({super.key});

  @override
  State<PaywallBottomSheet> createState() => _PaywallBottomSheetState();
}

class _PaywallBottomSheetState extends State<PaywallBottomSheet> {
  final PaymentService _paymentService = PaymentService();
  List<Package> _packages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    final packages = await _paymentService.getOfferings();
    if (mounted) {
      setState(() {
        _packages = packages;
        _isLoading = false;
      });
    }
  }
  
  // Função para tratar clique no produto Mock
  void _handleMockProductClick() {
    _showMockPurchaseDialog();
  }

  Future<void> _purchase(Package package) async {
    setState(() => _isLoading = true);
    
    // MOCK: Se for o pacote 'monthly_mock' (vamos adicionar isso), simula sucesso
    // Ou se quisermos facilitar, vamos colocar um botão escondido ou tratar erro
    
    // SIMULAÇÃO TEMPORÁRIA (Para testes sem configurar RevenueCat)
    // Se a compra falhar (porque não tem chave), perguntamos se quer simular sucesso.
    
    try {
      final success = await _paymentService.purchasePackage(package);
      if (success) {
        if (mounted) {
          Navigator.pop(context); // Fecha Paywall
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("💎 Bem-vindo ao Escudo Premium!")),
          );
          // Atualiza Controller
          context.read<TrialController>().checkTrialStatus();
        }
      } else {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text("Compra cancelada ou falhou.")),
           );
        }
      }
    } catch (e) {
      // Fallback para Mock se der erro de configuração (esperado agora)
      _showMockPurchaseDialog();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMockPurchaseDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Modo de Teste"),
        content: const Text("A configuração do RevenueCat ainda não está ativa. Deseja SIMULAR uma compra com sucesso?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _simulateSuccess();
            }, 
            child: const Text("Simular Sucesso")
          ),
        ],
      ),
    );
  }

  Future<void> _simulateSuccess() async {
     await context.read<TrialController>().simulatePurchaseSuccess();
     if (mounted) {
        Navigator.pop(context); // Fecha Paywall
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("💎 [MOCK] Assinatura Premium Ativada!")),
        );
     }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star, size: 48, color: Colors.amber),
          const SizedBox(height: 16),
          const Text(
            "Desbloqueie o Escudo Premium",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            "Remova anúncios, desbloqueie o histórico completo e proteja-se com IA avançada.",
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (_isLoading)
            const CircularProgressIndicator()
          else if (_packages.isEmpty)
             // EXIBE MOCK PRODUCT SE LISTA VAZIA
             _buildMockProductCard()
          else
            ..._packages.map((pkg) => ListTile(
              title: Text(pkg.storeProduct.title, style: const TextStyle(color: Colors.white)),
              subtitle: Text(pkg.storeProduct.description, style: const TextStyle(color: Colors.grey)),
              trailing: Text(pkg.storeProduct.priceString, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
              onTap: () => _purchase(pkg),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Colors.amber),
              ),
            )),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
  
  Widget _buildMockProductCard() {
    return Card(
      color: Colors.amber.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.amber),
      ),
      child: ListTile(
        leading: const Icon(Icons.diamond, color: Colors.amber),
        title: const Text(
          "Assinatura Mensal (Simulação)", 
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
        ),
        subtitle: const Text(
          "Teste o fluxo de compra completo", 
          style: TextStyle(color: Colors.grey)
        ),
        trailing: const Text(
          "R\$ 19,90", 
          style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)
        ),
        onTap: _handleMockProductClick,
      ),
    );
  }
}
