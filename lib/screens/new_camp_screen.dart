import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'campaigns_screen.dart';
import 'os_detail_screen.dart';

class NewCampScreen extends StatelessWidget {
  const NewCampScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppTopBar(title: 'Nova Coleta', subtitle: 'Como deseja iniciar?'),
      body: SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _SectionLabel('Tarefa atribuída'),

          // Open assigned OS
          GestureDetector(
            onTap: () {
              context.read<AppState>().startCampaign('cubatao');
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const CampaignsScreen()));
            },
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.tealLt,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x591A8A8A)),
              ),
              child: Row(children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(color: const Color(0x2E1A8A8A), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.layers_outlined, color: AppColors.teal, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Abrir OS atribuída', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.tealDk)),
                  const Text('Ordens de serviço designadas pelo seu coordenador ou gerente', style: TextStyle(fontSize: 11, color: AppColors.sub, height: 1.5)),
                  const SizedBox(height: 8),
                  Row(children: [
                    _SmallPill('1 em campo', AppColors.tealLt, AppColors.teal),
                    const SizedBox(width: 6),
                    _SmallPill('2 novas', AppColors.raised, AppColors.sub),
                  ]),
                ])),
                const Text('›', style: TextStyle(fontSize: 20, color: AppColors.teal, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),

          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 16),
            child: Text(
              'Use esta opção quando seu superior já criou a OS no sistema com os pontos, parâmetros e prazo definidos.',
              style: TextStyle(fontSize: 9, color: AppColors.sub2, height: 1.6),
            ),
          ),

          const _SectionLabel('Coleta do zero'),

          // Free-form collection options
          AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Registre uma coleta pontual sem OS prévia. Escolha o tipo de dado:', style: TextStyle(fontSize: 11, color: AppColors.sub, height: 1.5)),
            const SizedBox(height: 14),
            _CollectTypeRow(
              emoji: '🌱',
              label: 'Inventário de Nascentes',
              sub: 'pH · temperatura · condutividade · OD · turbidez',
              onTap: () => _start(context, 'nasc', 'Inventário de Nascentes'),
            ),
            _CollectTypeRow(
              emoji: '🌊',
              label: 'Monitoramento de Drenagens',
              sub: 'Vazão · turbidez · pH · OD',
              onTap: () => _start(context, 'dren', 'Monitoramento de Drenagens'),
            ),
            _CollectTypeRow(
              emoji: '📊',
              label: 'Monitoramento de Vertedouro',
              sub: 'Nível · vazão · qualidade da água',
              onTap: () => _start(context, 'vert', 'Monitoramento de Vertedouro'),
            ),
            _CollectTypeRow(
              emoji: '📏',
              label: 'Piezômetros / Instrumentação',
              sub: 'Nível · recalque · poropressão',
              onTap: () => _start(context, 'inst', 'Piezômetros / Instrumentação'),
              last: true,
            ),
          ])),

          const SizedBox(height: 40),
        ]),
      )),
    );
  }

  void _start(BuildContext context, String type, String name) {
    context.read<AppState>().startCampaign('livre');
    Navigator.push(context, MaterialPageRoute(builder: (_) => const OsDetailScreen()));
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: AppColors.sub)),
  );
}

class _SmallPill extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _SmallPill(this.label, this.bg, this.fg);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
  );
}

class _CollectTypeRow extends StatelessWidget {
  final String emoji;
  final String label;
  final String sub;
  final VoidCallback onTap;
  final bool last;
  const _CollectTypeRow({required this.emoji, required this.label, required this.sub, required this.onTap, this.last = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: EdgeInsets.only(bottom: last ? 0 : 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: AppColors.tealLt, borderRadius: BorderRadius.circular(11)),
          alignment: Alignment.center,
          child: Text(emoji, style: const TextStyle(fontSize: 18)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMain)),
          Text(sub, style: const TextStyle(fontSize: 10, color: AppColors.sub)),
        ])),
        const Text('›', style: TextStyle(fontSize: 16, color: AppColors.sub2, fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}
