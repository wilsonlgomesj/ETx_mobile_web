import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'os_detail_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _fromLabel = '01/2018';
  String _toLabel = '06/2021';
  String _ccLabel = 'Todos os centros de custo';
  final Set<String> _selectedReports = {};

  final List<_Report> _reports = [
    _Report(
      title: 'Campanha Paulínia — 04/2025',
      subtitle: 'Monitoramento BASF · 6 pontos · 04/04/2025',
      icon: Icons.description_outlined,
      statusLabel: 'Coletado',
      statusVariant: PillVariant.teal,
      hasFile: true,
    ),
    _Report(
      title: 'Campanha Paulínia — 03/2025',
      subtitle: 'Monitoramento BASF · 6 pontos · 03/03/2025',
      icon: Icons.description_outlined,
      statusLabel: 'Coletado',
      statusVariant: PillVariant.teal,
      hasFile: true,
    ),
    _Report(
      title: 'Campanha Vale Carajás — 01/2025',
      subtitle: 'Vale S.A. · 8 pontos · 15/01/2025',
      icon: Icons.description_outlined,
      statusLabel: 'Coletado',
      statusVariant: PillVariant.teal,
      hasFile: true,
    ),
    _Report(
      title: 'Campanha Cubatão — Q4/2024',
      subtitle: 'Petrobras · 4 pontos · 10/11/2024',
      icon: Icons.description_outlined,
      statusLabel: 'Coletado',
      statusVariant: PillVariant.teal,
      hasFile: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 10),
          color: AppColors.surf,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Text.rich(TextSpan(children: [
                TextSpan(text: 'EcoFlow', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: AppColors.textMain)),
                TextSpan(text: 'App', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: AppColors.teal)),
              ])),
              Text('RELATÓRIOS', style: TextStyle(fontSize: 8, color: AppColors.sub2, letterSpacing: 2, fontWeight: FontWeight.w700)),
            ]),
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(color: AppColors.surf, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
              child: const Icon(Icons.notifications_outlined, size: 18, color: AppColors.sub),
            ),
          ]),
        ),
        Container(height: 1, color: AppColors.line),

        Expanded(child: ListView(children: [
          // Field reports entry
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OsDetailScreen())),
            child: Container(
              margin: const EdgeInsets.fromLTRB(24, 14, 24, 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surf, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
              child: Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: AppColors.tealLt, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.description_outlined, color: AppColors.teal, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Relatórios Técnicos de Campo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMain)),
                  Text('Formulários completos com fotos, parâmetros e assinatura digital', style: TextStyle(fontSize: 10, color: AppColors.sub, height: 1.4)),
                ])),
                const Text('›', style: TextStyle(fontSize: 18, color: AppColors.sub2)),
              ]),
            ),
          ),

          // Filter card
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('FILTROS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: AppColors.sub)),
              const SizedBox(height: 12),

              const Text('Período', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.sub)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: _DatePicker(label: _fromLabel, onTap: () {})),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('→', style: TextStyle(fontSize: 14, color: AppColors.sub2))),
                Expanded(child: _DatePicker(label: _toLabel, onTap: () {})),
              ]),
              const SizedBox(height: 12),

              const Text('Centro de Custo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.sub)),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () {},
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(_ccLabel, style: const TextStyle(fontSize: 13, color: AppColors.textMain)),
                    const Text('▾', style: TextStyle(fontSize: 14, color: AppColors.sub)),
                  ]),
                ),
              ),
              const SizedBox(height: 12),

              const Text('Tipo de ponto', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.sub)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: const [
                _TypeChip('🌱 Nascentes', true),
                _TypeChip('🌊 Drenagens', false),
                _TypeChip('📏 Piezômetros', false),
                _TypeChip('🌊 Vertedouros', false),
              ]),
              const SizedBox(height: 12),

              Row(children: [
                Expanded(child: TealButton(label: 'Aplicar filtros', onTap: () {})),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {},
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
                    child: const Text('Limpar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.sub)),
                  ),
                ),
              ]),
            ])),
          ),

          // Reports list header with select all
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${_reports.length} relatórios encontrados', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: AppColors.sub)),
              Row(children: [
                GestureDetector(
                  onTap: () {},
                  child: const Text('📄 Exportar PDF', style: TextStyle(fontSize: 11, color: AppColors.teal, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {},
                  child: const Text('📊 Excel', style: TextStyle(fontSize: 11, color: AppColors.teal, fontWeight: FontWeight.w700)),
                ),
              ]),
            ]),
          ),

          ..._reports.map((r) => _ReportCard(
            report: r,
            selected: _selectedReports.contains(r.title),
            onSelect: () => setState(() {
              if (_selectedReports.contains(r.title)) _selectedReports.remove(r.title);
              else _selectedReports.add(r.title);
            }),
          )),

          const SizedBox(height: 80),
        ])),
      ])),
      bottomNavigationBar: MainTabBar(currentIndex: 2, onTap: (i) => _handleTab(context, i)),
    );
  }

  void _handleTab(BuildContext context, int i) {
    switch (i) {
      case 0: Navigator.of(context).popUntil((r) => r.isFirst); break;
      case 1: Navigator.of(context).pushNamed('/campaigns'); break;
      case 2: break;
      case 3: Navigator.of(context).pushNamed('/calendar'); break;
      case 4: Navigator.of(context).pushNamed('/profile'); break;
    }
  }
}

class _DatePicker extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DatePicker({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
      child: Row(children: [
        const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.sub),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMain)),
      ]),
    ),
  );
}

class _TypeChip extends StatelessWidget {
  final String label;
  final bool active;
  const _TypeChip(this.label, this.active);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: active ? AppColors.tealLt : AppColors.bg,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: active ? const Color(0x4D1A8A8A) : AppColors.line),
    ),
    child: Text(label, style: TextStyle(fontSize: 11, color: active ? AppColors.teal : AppColors.sub, fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
  );
}

class _Report {
  final String title;
  final String subtitle;
  final IconData icon;
  final String statusLabel;
  final PillVariant statusVariant;
  final bool hasFile;
  const _Report({required this.title, required this.subtitle, required this.icon, required this.statusLabel, required this.statusVariant, required this.hasFile});
}

class _ReportCard extends StatelessWidget {
  final _Report report;
  final bool selected;
  final VoidCallback onSelect;
  const _ReportCard({required this.report, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onSelect,
    child: Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected ? AppColors.tealLt : AppColors.surf,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: selected ? const Color(0x591A8A8A) : AppColors.line),
      ),
      child: Row(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 20, height: 20,
          decoration: BoxDecoration(
            color: selected ? AppColors.teal : AppColors.bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: selected ? AppColors.teal : AppColors.line, width: 1.5),
          ),
          child: selected ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
        ),
        const SizedBox(width: 12),
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: AppColors.tealLt, borderRadius: BorderRadius.circular(10)),
          child: Icon(report.icon, color: AppColors.teal, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(report.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMain)),
          Text(report.subtitle, style: const TextStyle(fontSize: 10, color: AppColors.sub)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          PillBadge(report.statusLabel, variant: report.statusVariant),
          if (report.hasFile) ...[
            const SizedBox(height: 6),
            const Icon(Icons.picture_as_pdf_outlined, size: 14, color: AppColors.sub),
          ],
        ]),
      ]),
    ),
  );
}
