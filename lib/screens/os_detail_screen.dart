import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'collect_screen.dart';
import 'finish_screen.dart';

class OsDetailScreen extends StatelessWidget {
  const OsDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final camp = state.activeCampaign;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppTopBar(
        title: camp?.name ?? 'Ordem de Serviço',
        subtitle: camp?.code ?? '',
      ),
      body: SingleChildScrollView(child: Column(children: [

        // Progress card
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
          child: AppCard(child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(camp?.name ?? 'Campanha', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textMain)),
                Text(camp?.client ?? '', style: const TextStyle(fontSize: 11, color: AppColors.sub)),
              ])),
              Text(
                '${(state.progress * 100).toInt()}%',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.teal),
              ),
            ]),
            const SizedBox(height: 12),
            AppProgressBar(value: state.progress),
            const SizedBox(height: 14),
            Row(children: [
              _Stat('${state.doneCount}', 'coletados', AppColors.teal),
              _StatDivider(),
              _Stat('${state.pendCount}', 'pendentes', AppColors.textMain),
              _StatDivider(),
              _Stat('${state.ncCount}', 'não colet.', AppColors.sub2),
            ]),
          ])),
        ),

        // Meta row
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Row(children: [
            _MetaChip('CLIENTE', camp?.client.split('·').first.trim() ?? '—'),
            const SizedBox(width: 8),
            _MetaChip('PRAZO', camp?.deadline ?? '—'),
            const SizedBox(width: 8),
            _MetaChip('RESP.', camp?.responsible ?? '—'),
          ]),
        ),

        // Tags
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
          child: Wrap(spacing: 6, children: const [
            PillBadge('● NASC', variant: PillVariant.teal),
            PillBadge('● DRN',  variant: PillVariant.teal),
            PillBadge('● PZ',   variant: PillVariant.neutral),
          ]),
        ),

        // Next recommended
        if (state.nextPendingIndex >= 0) _NextCard(
          point: state.points[state.nextPendingIndex],
          index: state.nextPendingIndex,
        ),

        // Points list
        const SectionHeader('Pontos de coleta'),
        ...List.generate(state.points.length, (i) => _PointRow(
          point: state.points[i],
          index: i,
          isNext: i == state.nextPendingIndex,
          onTap: () {
            context.read<AppState>().openPoint(i);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const CollectScreen()));
          },
        )),

        const SizedBox(height: 16),

        // Action button
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: TealButton(
            label: state.progress >= 1.0 ? '✅ Encerrar campanha' : '▶  Iniciar próximo ponto',
            color: state.progress >= 1.0 ? AppColors.green : AppColors.teal,
            onTap: () {
              if (state.progress >= 1.0) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const FinishScreen()));
              } else if (state.nextPendingIndex >= 0) {
                context.read<AppState>().openPoint(state.nextPendingIndex);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const CollectScreen()));
              }
            },
          ),
        ),

        const SizedBox(height: 40),
      ])),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _Stat(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Expanded(child: Column(children: [
    Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
    Text(label, style: const TextStyle(fontSize: 8, color: AppColors.sub, letterSpacing: 0.5)),
  ]));
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(width: 1, height: 24, color: AppColors.line);
}

class _MetaChip extends StatelessWidget {
  final String label;
  final String value;
  const _MetaChip(this.label, this.value);

  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppColors.surf,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w700, color: AppColors.sub2, letterSpacing: 1)),
      Text(value, style: const TextStyle(fontSize: 11, color: AppColors.textMain, fontWeight: FontWeight.w600)),
    ]),
  ));
}

class _NextCard extends StatelessWidget {
  final FieldPoint point;
  final int index;
  const _NextCard({required this.point, required this.index});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      context.read<AppState>().openPoint(index);
      Navigator.push(context, MaterialPageRoute(builder: (_) => const CollectScreen()));
    },
    child: Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.navigation_outlined, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('PRÓXIMO RECOMENDADO', style: TextStyle(fontSize: 8, color: Color(0x99FFFFFF), letterSpacing: 1.3, fontWeight: FontWeight.w700)),
          Text(point.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
          Text('${point.typeLabel} · ${point.code}', style: const TextStyle(fontSize: 10, color: Color(0xA6FFFFFF))),
        ])),
        const Text('›', style: TextStyle(fontSize: 20, color: Color(0x66FFFFFF), fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}

class _PointRow extends StatelessWidget {
  final FieldPoint point;
  final int index;
  final bool isNext;
  final VoidCallback onTap;
  const _PointRow({required this.point, required this.index, required this.isNext, required this.onTap});

  (Color, Color) get _numberStyle {
    switch (point.status) {
      case PointStatus.done: return (AppColors.tealLt, AppColors.teal);
      case PointStatus.nc:   return (const Color(0x1AF07A2A), AppColors.warn);
      case PointStatus.pending:
        return isNext ? (AppColors.teal, Colors.white) : (AppColors.bg, AppColors.sub);
    }
  }

  Color get _rowBorder {
    if (isNext) return const Color(0x591A8A8A);
    if (point.status == PointStatus.nc) return const Color(0x4DF07A2A);
    return AppColors.line;
  }

  Color get _rowBg {
    if (isNext) return AppColors.tealLt;
    if (point.status == PointStatus.nc) return const Color(0x0AF07A2A);
    return AppColors.surf;
  }

  @override
  Widget build(BuildContext context) {
    final (numBg, numFg) = _numberStyle;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 6),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: _rowBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _rowBorder),
        ),
        child: Row(children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(color: numBg, shape: BoxShape.circle, border: Border.all(color: _rowBorder)),
            alignment: Alignment.center,
            child: point.status == PointStatus.done
              ? Icon(Icons.check, size: 13, color: numFg)
              : Text('${index + 1}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: numFg)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(point.code, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.sub, letterSpacing: 0.8)),
            Text(point.name, style: const TextStyle(fontSize: 13, color: AppColors.textMain)),
            Text(point.typeLabel, style: const TextStyle(fontSize: 10, color: AppColors.sub)),
          ])),
          if (point.status == PointStatus.done)
            const PillBadge('Coletado')
          else if (point.status == PointStatus.nc)
            const PillBadge('Não coletado', variant: PillVariant.warn)
          else if (isNext)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: AppColors.tealLt, borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: const [
                SizedBox(width: 6, height: 6, child: DecoratedBox(decoration: BoxDecoration(color: AppColors.teal, shape: BoxShape.circle))),
                SizedBox(width: 5),
                Text('Iniciar', style: TextStyle(fontSize: 10, color: AppColors.teal, fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
      ),
    );
  }
}
