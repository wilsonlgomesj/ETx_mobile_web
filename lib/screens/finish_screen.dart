import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../stabilization/stabilization_models.dart';
import '../stabilization/stabilization_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class FinishScreen extends StatefulWidget {
  const FinishScreen({super.key});

  @override
  State<FinishScreen> createState() => _FinishScreenState();
}

class _FinishScreenState extends State<FinishScreen> {
  bool _signed = false;
  final _obsController = TextEditingController();
  final _timeController = TextEditingController(text: '17:42');

  @override
  void dispose() {
    _obsController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  void _finish(BuildContext context) {
    context.read<AppState>().finishCampaign();
    showToast(context, '☁️ Campanha enviada com sucesso!');
    // Pop back to root
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppTopBar(title: 'Encerramento', subtitle: 'Finalizar campanha de campo'),
      body: SingleChildScrollView(child: Column(children: [

        // Hero banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.teal, AppColors.tealDk],
            ),
          ),
          child: Column(children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
              child: const Icon(Icons.check_circle_outline, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 12),
            Text(
              state.doneCount == state.points.length ? 'Campanha concluída!' : 'Encerrar campanha',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              '${state.doneCount} pontos coletados · ${state.ncCount} não conformidades',
              style: const TextStyle(fontSize: 12, color: Color(0xB3FFFFFF), height: 1.5),
            ),
          ]),
        ),

        // Stats
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
          child: Row(children: [
            _StatCard('${state.doneCount}', 'Coletados', AppColors.teal),
            const SizedBox(width: 8),
            _StatCard('${state.ncCount}', 'Não coletados', AppColors.warn),
            const SizedBox(width: 8),
            _StatCard('${(state.progress * 100).toInt()}%', 'Cobertura', AppColors.green),
          ]),
        ),

        // Time / duration
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
          child: AppCard(child: Column(children: [
            const Align(alignment: Alignment.centerLeft, child: Text('HORÁRIO DE ENCERRAMENTO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppColors.sub))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('HORA', style: TextStyle(fontSize: 9, color: AppColors.sub2)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.line)),
                  child: Text(_timeController.text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.teal)),
                ),
              ])),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('DURAÇÃO', style: TextStyle(fontSize: 9, color: AppColors.sub2)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.line)),
                  child: const Text('~3h40', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.sub)),
                ),
              ])),
            ]),
          ])),
        ),

        // Closing observation
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('OBSERVAÇÃO DE ENCERRAMENTO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppColors.sub)),
            const SizedBox(height: 6),
            TextField(
              controller: _obsController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Condições gerais do campo, ocorrências, próximos passos…',
                hintStyle: const TextStyle(fontSize: 12, color: AppColors.sub2),
                filled: true,
                fillColor: AppColors.surf,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.teal)),
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
          ]),
        ),

        // Digital Signature
        const SectionHeader('Assinatura Digital do Técnico Responsável'),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surf,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line, style: BorderStyle.solid, width: 1.5),
            ),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Consumer<AppState>(builder: (ctx, s, _) => Text('${s.userName} · ${s.userRole} · ${s.userReg}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.sub))),
                    Text(
                      _signed ? 'Assinado em ${DateTime.now().day.toString().padLeft(2,'0')}/${DateTime.now().month.toString().padLeft(2,'0')}/${DateTime.now().year}' : 'Aguardando assinatura…',
                      style: const TextStyle(fontSize: 9, color: AppColors.sub2),
                    ),
                  ])),
                  GestureDetector(
                    onTap: () => setState(() => _signed = false),
                    child: const Text('Limpar', style: TextStyle(fontSize: 11, color: AppColors.teal, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
              Container(height: 1, color: AppColors.line2),
              GestureDetector(
                onTap: () => setState(() => _signed = true),
                child: Container(
                  height: 80,
                  alignment: Alignment.center,
                  child: _signed
                    ? Consumer<AppState>(builder: (ctx, s, _) => Text(s.userName, style: const TextStyle(fontSize: 22, fontStyle: FontStyle.italic, color: AppColors.teal, fontWeight: FontWeight.w700)))
                    : const Text('Toque aqui para assinar', style: TextStyle(fontSize: 11, color: AppColors.sub2)),
                ),
              ),
            ]),
          ),
        ),

        // QAQC Summary
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
          child: AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('RESUMO QAQC DA CAMPANHA', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppColors.sub)),
            const SizedBox(height: 10),
            _QaqcRow('Cobertura fotográfica', '${state.doneCount * 3}/${state.points.length * 3} fotos', AppColors.teal),
            _QaqcRow('Checklist POP cumprido', '${state.doneCount}/${state.points.length} pontos', AppColors.teal),
            _QaqcRow('Pontos com variação >20%', state.ncCount > 0 ? '${state.ncCount} pontos' : 'Nenhum', state.ncCount > 0 ? AppColors.warn : AppColors.green),
            _QaqcRow('Itens na fila de sync', '${state.syncPending} pendentes', AppColors.sub),
            // ── Stabilization QAQC ──────────────────────────────────────────
            if (state.activeCampaignId != null)
              _StabilizationQaqcSection(campaignId: state.activeCampaignId!),
          ])),
        ),

        // Buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
          child: TealButton(label: '☁️ Enviar e encerrar campanha', onTap: () => _finish(context)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
          child: GestureDetector(
            onTap: () => showToast(context, '📄 PDF gerado!'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surf,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.line),
              ),
              alignment: Alignment.center,
              child: const Text('📄 Gerar PDF de encerramento', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textMain)),
            ),
          ),
        ),
      ])),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _StatCard(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
    decoration: BoxDecoration(
      color: AppColors.surf,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(children: [
      Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: color)),
      Text(label, style: const TextStyle(fontSize: 8, color: AppColors.sub, letterSpacing: 0.5), textAlign: TextAlign.center),
    ]),
  ));
}

class _QaqcRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _QaqcRow(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 6),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line2))),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMain)),
      Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// STABILIZATION QAQC SECTION
// Loaded asynchronously from DB so it never blocks the FinishScreen render.
// Integration point for PDF/Excel: pass StabilizationQaqc to report generator.
// ─────────────────────────────────────────────────────────────────────────────

class _StabilizationQaqcSection extends StatelessWidget {
  final String campaignId;
  const _StabilizationQaqcSection({required this.campaignId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StabilizationQaqc>(
      future: StabilizationRepository.instance.getQaqcForCampaign(campaignId),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal))),
          );
        }

        final q = snap.data!;

        // No points with stabilization requirements — nothing to show.
        if (q.totalWithStabilization == 0) return const SizedBox.shrink();

        final rateColor = q.conformanceRate >= 90
            ? AppColors.green
            : q.conformanceRate >= 70
                ? AppColors.warn
                : AppColors.danger;

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.only(top: 10, bottom: 4),
            child: Text('ESTABILIZAÇÃO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppColors.sub)),
          ),
          _QaqcRow(
            'Pontos com estabilização',
            '${q.totalWithStabilization} pontos',
            AppColors.sub,
          ),
          _QaqcRow(
            'Estabilizados corretamente',
            '${q.stabilized}/${q.totalWithStabilization}',
            q.stabilized == q.totalWithStabilization ? AppColors.green : AppColors.warn,
          ),
          _QaqcRow(
            'Salvos com exceção justificada',
            q.withException > 0 ? '${q.withException} pontos' : 'Nenhum',
            q.withException > 0 ? const Color(0xFF7B1FA2) : AppColors.green,
          ),
          _QaqcRow(
            'Fora do critério (sem justif.)',
            q.outOfRange > 0 ? '${q.outOfRange} pontos' : 'Nenhum',
            q.outOfRange > 0 ? AppColors.danger : AppColors.green,
          ),
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: rateColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: rateColor.withValues(alpha: 0.3)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Conformidade de estabilização', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMain)),
              Text('${q.conformanceRate.toStringAsFixed(0)}%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: rateColor)),
            ]),
          ),
        ]);
      },
    );
  }
}
