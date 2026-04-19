import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'new_camp_screen.dart';
import 'os_detail_screen.dart';

class CampaignsScreen extends StatefulWidget {
  const CampaignsScreen({super.key});

  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends State<CampaignsScreen> {
  String _filter = 'todas';

  List<Campaign> _filtered(List<Campaign> all) {
    if (_filter == 'todas') return all;
    return all.where((c) {
      switch (_filter) {
        case 'em_campo':  return c.status == OperationalStatus.emCampo;
        case 'atrasada':  return c.status == OperationalStatus.atrasada;
        case 'nova':      return c.status == OperationalStatus.nova;
        case 'concluida': return c.status == OperationalStatus.concluida;
        default:          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final campaigns = context.watch<AppState>().campaigns;
    final inField = campaigns.where((c) => c.status == OperationalStatus.emCampo).length;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppTopBar(
        title: 'Campanhas',
        subtitle: '${campaigns.length} campanhas · $inField em campo',
      ),
      body: Column(children: [
        // Filters
        Container(
          color: AppColors.surf,
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              _FilterChip('Todas',     'todas',     _filter, _setFilter),
              _FilterChip('Em campo',  'em_campo',  _filter, _setFilter),
              _FilterChip('Atrasadas', 'atrasada',  _filter, _setFilter),
              _FilterChip('Novas',     'nova',      _filter, _setFilter),
              _FilterChip('Concluídas','concluida', _filter, _setFilter),
            ],
          ),
        ),

        Expanded(child: ListView(children: [
          // Nova coleta CTA
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewCampScreen())),
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.add_circle_outline, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Nova coleta', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                  Text('Criar registro de monitoramento do zero', style: TextStyle(fontSize: 11, color: Color(0xA6FFFFFF))),
                ])),
                const Text('›', style: TextStyle(fontSize: 20, color: Color(0x66FFFFFF), fontWeight: FontWeight.w700)),
              ]),
            ),
          ),

          Container(height: 1, color: AppColors.line, margin: const EdgeInsets.fromLTRB(20, 4, 20, 10)),
          const SectionHeader('Campanhas ativas', padding: EdgeInsets.fromLTRB(20, 0, 20, 10)),

          ..._filtered(campaigns).map((c) => _CampaignCard(campaign: c, onTap: () {
            context.read<AppState>().startCampaign(c.id);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const OsDetailScreen()));
          })),

          const SizedBox(height: 80),
        ])),
      ]),
      bottomNavigationBar: MainTabBar(
        currentIndex: 1,
        onTap: _handleTab,
      ),
    );
  }

  void _setFilter(String f) => setState(() => _filter = f);

  void _handleTab(int i) {
    switch (i) {
      case 0: Navigator.of(context).popUntil((r) => r.isFirst); break;
      case 1: break;
      case 2: Navigator.of(context).pushNamed('/reports'); break;
      case 3: Navigator.of(context).pushNamed('/calendar'); break;
      case 4: Navigator.of(context).pushNamed('/profile'); break;
    }
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String current;
  final ValueChanged<String> onTap;
  const _FilterChip(this.label, this.value, this.current, this.onTap);

  @override
  Widget build(BuildContext context) {
    final active = value == current;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppColors.tealLt : AppColors.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? const Color(0x591A8A8A) : AppColors.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.w600,
            color: active ? AppColors.teal : AppColors.sub,
          ),
        ),
      ),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  final Campaign campaign;
  final VoidCallback onTap;
  const _CampaignCard({required this.campaign, required this.onTap});

  (Color, Color, Color, String) get _statusStyle {
    switch (campaign.status) {
      case OperationalStatus.emCampo:
        return (AppColors.tealLt, AppColors.teal, AppColors.teal, 'Em campo');
      case OperationalStatus.nova:
        return (AppColors.raised, AppColors.sub2, AppColors.sub, 'Nova');
      case OperationalStatus.atrasada:
        return (const Color(0x14DC2626), AppColors.danger, AppColors.danger, 'Atrasada');
      case OperationalStatus.concluida:
        return (const Color(0x1A16A34A), AppColors.green, AppColors.green, 'Concluída');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (pillBg, pillFg, _, statusLabel) = _statusStyle;
    final isDelayed = campaign.status == OperationalStatus.atrasada;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surf,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDelayed ? const Color(0x40DC2626) : AppColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(campaign.code, style: const TextStyle(fontSize: 9, color: AppColors.sub2, letterSpacing: 1, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: pillBg, borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 5, height: 5, decoration: BoxDecoration(color: pillFg, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(statusLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: pillFg)),
              ]),
            ),
          ]),
          const SizedBox(height: 4),
          Text(campaign.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textMain)),
          Text(campaign.client, style: const TextStyle(fontSize: 11, color: AppColors.sub)),
          const SizedBox(height: 8),
          AppProgressBar(
            value: campaign.progress,
            color: isDelayed ? AppColors.danger : null,
          ),
          const SizedBox(height: 5),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(
              '${campaign.donePoints}/${campaign.totalPoints} pontos · ${campaign.totalPoints - campaign.donePoints} pendentes',
              style: const TextStyle(fontSize: 10, color: AppColors.sub, fontWeight: FontWeight.w600),
            ),
            Text(
              campaign.donePoints > 0 ? 'Último registro hoje' : '',
              style: const TextStyle(fontSize: 10, color: AppColors.teal),
            ),
          ]),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(
              isDelayed ? '⚠ Prazo: ${campaign.deadline}' : 'Prazo: ${campaign.deadline}',
              style: TextStyle(fontSize: 10, color: isDelayed ? AppColors.danger : AppColors.sub2),
            ),
            Text('Resp.: ${campaign.responsible}', style: const TextStyle(fontSize: 10, color: AppColors.sub2)),
          ]),
        ]),
      ),
    );
  }
}
