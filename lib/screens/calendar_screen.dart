import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

enum CalView { week, month, year }

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalView _view = CalView.week;
  DateTime _selected = DateTime.now();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  final List<_CalEvent> _events = [
    _CalEvent(
      name: 'Monitoramento Paulínia',
      client: 'BASF S.A.',
      region: 'Campinas / SP',
      time: '07:00',
      status: 'Em campo',
      statusColor: AppColors.teal,
      date: DateTime.now(),
    ),
    _CalEvent(
      name: 'Vale Carajás — Pré-campo',
      client: 'Vale S.A.',
      region: 'Marabá / PA',
      time: '08:30',
      status: 'Nova',
      statusColor: AppColors.sub,
      date: DateTime.now().add(const Duration(days: 2)),
    ),
    _CalEvent(
      name: 'Cubatão — Pendência',
      client: 'Petrobras',
      region: 'Cubatão / SP',
      time: '09:00',
      status: 'Atrasada',
      statusColor: AppColors.danger,
      date: DateTime.now().add(const Duration(days: 5)),
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
              Text('CALENDÁRIO DE CAMPO', style: TextStyle(fontSize: 8, color: AppColors.sub2, letterSpacing: 2, fontWeight: FontWeight.w700)),
            ]),
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(color: AppColors.surf, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
              child: const Icon(Icons.add, size: 18, color: AppColors.teal),
            ),
          ]),
        ),
        Container(height: 1, color: AppColors.line),

        // View switcher
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 4),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: AppColors.raised, borderRadius: BorderRadius.circular(12)),
            child: Row(children: CalView.values.map((v) {
              final active = v == _view;
              final label = v == CalView.week ? 'Semana' : v == CalView.month ? 'Mês' : 'Ano';
              return Expanded(child: GestureDetector(
                onTap: () => setState(() => _view = v),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: active ? AppColors.surf : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: active ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 3, offset: const Offset(0,1))] : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(label, style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.w600, color: active ? AppColors.teal : AppColors.sub)),
                ),
              ));
            }).toList()),
          ),
        ),

        // Legend
        SizedBox(
          height: 30,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            children: const [
              _LegendItem('Em campo', AppColors.teal),
              SizedBox(width: 10),
              _LegendItem('Nova', AppColors.sub2),
              SizedBox(width: 10),
              _LegendItem('Atrasada', AppColors.danger),
              SizedBox(width: 10),
              _LegendItem('Concluída', AppColors.green),
            ],
          ),
        ),

        Expanded(child: _buildView()),
      ])),
      bottomNavigationBar: MainTabBar(currentIndex: 3, onTap: (i) => _handleTab(context, i)),
    );
  }

  Widget _buildView() {
    switch (_view) {
      case CalView.week:  return _buildWeekView();
      case CalView.month: return _buildMonthView();
      case CalView.year:  return _buildYearView();
    }
  }

  // ── WEEK VIEW ─────────────────────────────────────────────
  Widget _buildWeekView() {
    final today = DateTime.now();
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final dayNames = ['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SÁB', 'DOM'];

    return Column(children: [
      // Week nav
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _CalNavBtn(icon: Icons.chevron_left, onTap: () {}),
          const Text('Semana atual', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMain)),
          _CalNavBtn(icon: Icons.chevron_right, onTap: () {}),
        ]),
      ),

      // Week summary
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        child: AppCard(child: Row(children: [
          _WeekStat('1', 'campanhas'),
          Container(width: 1, height: 28, color: AppColors.line),
          _WeekStat('6', 'pontos'),
          Container(width: 1, height: 28, color: AppColors.line),
          _WeekStat('4', 'pendentes'),
        ])),
      ),

      // Day strip
      SizedBox(
        height: 70,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          children: List.generate(7, (i) {
            final day = days[i];
            final isToday = day.day == today.day && day.month == today.month;
            final isSel = day.day == _selected.day && day.month == _selected.month;
            return GestureDetector(
              onTap: () => setState(() => _selected = day),
              child: Container(
                width: 54, margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: isSel ? AppColors.tealLt : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(dayNames[i], style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: isSel ? AppColors.teal : AppColors.sub2, letterSpacing: 0.5)),
                  const SizedBox(height: 4),
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: isSel ? AppColors.teal : isToday ? AppColors.tealLt : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text('${day.day}', style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: isSel ? Colors.white : isToday ? AppColors.teal : AppColors.textMain,
                    )),
                  ),
                ]),
              ),
            );
          }),
        ),
      ),

      Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 80), children: [
        ..._eventsForDay(_selected).map((e) => _EventCard(event: e)),
        if (_eventsForDay(_selected).isEmpty)
          Center(child: Padding(
            padding: const EdgeInsets.all(16),
            child: AppCard(child: const Column(children: [
              Text('📅', style: TextStyle(fontSize: 24)),
              SizedBox(height: 8),
              Text('Nenhuma atividade neste dia', style: TextStyle(fontSize: 11, color: AppColors.sub2, letterSpacing: 1)),
            ])),
          )),
      ])),
    ]);
  }

  // ── MONTH VIEW ────────────────────────────────────────────
  Widget _buildMonthView() {
    final year  = _month.year;
    final month = _month.month;
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startOffset = (firstDay.weekday - 1) % 7;
    final today = DateTime.now();
    final monthNames = ['Janeiro','Fevereiro','Março','Abril','Maio','Junho','Julho','Agosto','Setembro','Outubro','Novembro','Dezembro'];
    final dayLabels = ['S','T','Q','Q','S','S','D'];

    return ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 80), children: [
      AppCard(child: Column(children: [
        // Month nav
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${monthNames[month-1]} $year', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textMain)),
          Row(children: [
            _CalNavBtn(icon: Icons.chevron_left, onTap: () => setState(() => _month = DateTime(year, month-1))),
            const SizedBox(width: 6),
            _CalNavBtn(icon: Icons.chevron_right, onTap: () => setState(() => _month = DateTime(year, month+1))),
          ]),
        ]),
        const SizedBox(height: 10),

        // Summary pills
        Wrap(spacing: 8, children: [
          _MonthSumPill('1 campanha', AppColors.tealLt, AppColors.teal),
          _MonthSumPill('6 pontos', AppColors.raised, AppColors.sub),
          _MonthSumPill('1 atrasada', const Color(0x1ADC2626), AppColors.danger),
        ]),
        const SizedBox(height: 12),

        // Day labels
        Row(children: dayLabels.map((l) => Expanded(child: Center(child: Text(l, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.sub2, letterSpacing: 1))))).toList()),
        const SizedBox(height: 6),

        // Day grid
        Wrap(children: [
          ...List.generate(startOffset, (_) => const SizedBox(width: 0)), // Padding
          ...List.generate(daysInMonth, (i) {
            final day = i + 1;
            final isToday = today.year == year && today.month == month && today.day == day;
            final isSel = _selected.year == year && _selected.month == month && _selected.day == day;
            final hasEvent = _events.any((e) => e.date.year == year && e.date.month == month && e.date.day == day);
            return SizedBox(
              width: (MediaQuery.of(context).size.width - 48 - 28) / 7,
              child: GestureDetector(
                onTap: () => setState(() => _selected = DateTime(year, month, day)),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 2),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        color: isSel ? AppColors.teal : isToday ? AppColors.tealLt : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text('$day', style: TextStyle(fontSize: 12, color: isSel ? Colors.white : isToday ? AppColors.teal : AppColors.textMain, fontWeight: (isSel || isToday) ? FontWeight.w700 : FontWeight.w400)),
                    ),
                    if (hasEvent)
                      Container(width: 4, height: 4, decoration: const BoxDecoration(color: AppColors.teal, shape: BoxShape.circle)),
                  ]),
                ),
              ),
            );
          }),
        ]),
      ])),

      const SizedBox(height: 12),
      ..._eventsForDay(_selected).map((e) => _EventCard(event: e)),
    ]);
  }

  // ── YEAR VIEW ─────────────────────────────────────────────
  Widget _buildYearView() {
    final today = DateTime.now();
    final monthNames = ['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez'];
    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.1,
      children: List.generate(12, (mi) {
        final isCur = mi + 1 == today.month;
        return GestureDetector(
          onTap: () => setState(() { _month = DateTime(today.year, mi+1); _view = CalView.month; }),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surf,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isCur ? AppColors.teal : AppColors.line, width: isCur ? 1.5 : 1),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(monthNames[mi], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: isCur ? AppColors.teal : AppColors.textMain, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              Expanded(child: _MiniMonthGrid(year: today.year, month: mi+1, events: _events)),
            ]),
          ),
        );
      }),
    );
  }

  List<_CalEvent> _eventsForDay(DateTime day) =>
    _events.where((e) => e.date.year == day.year && e.date.month == day.month && e.date.day == day.day).toList();

  void _handleTab(BuildContext context, int i) {
    switch (i) {
      case 0: Navigator.of(context).popUntil((r) => r.isFirst); break;
      case 1: Navigator.of(context).pushNamed('/campaigns'); break;
      case 2: Navigator.of(context).pushNamed('/reports'); break;
      case 3: break;
      case 4: Navigator.of(context).pushNamed('/profile'); break;
    }
  }
}

// ── MINI MONTH GRID ───────────────────────────────────────────
class _MiniMonthGrid extends StatelessWidget {
  final int year, month;
  final List<_CalEvent> events;
  const _MiniMonthGrid({required this.year, required this.month, required this.events});

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startOffset = (firstDay.weekday - 1) % 7;
    final today = DateTime.now();

    return Wrap(children: [
      ...List.generate(startOffset, (_) => const SizedBox(width: 0)),
      ...List.generate(daysInMonth, (i) {
        final day = i + 1;
        final isToday = today.year == year && today.month == month && today.day == day;
        final hasEvent = events.any((e) => e.date.year == year && e.date.month == month && e.date.day == day);
        return SizedBox(
          width: 18, height: 18,
          child: Stack(alignment: Alignment.center, children: [
            Container(
              width: 16, height: 16,
              decoration: BoxDecoration(
                color: isToday ? AppColors.teal : Colors.transparent,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text('$day', style: TextStyle(fontSize: 8, color: isToday ? Colors.white : AppColors.textMain, fontWeight: isToday ? FontWeight.w700 : FontWeight.w400)),
            ),
            if (hasEvent) Positioned(bottom: 0, child: Container(width: 3, height: 3, decoration: const BoxDecoration(color: AppColors.teal, shape: BoxShape.circle))),
          ]),
        );
      }),
    ]);
  }
}

// ── EVENT CARD ────────────────────────────────────────────────
class _EventCard extends StatelessWidget {
  final _CalEvent event;
  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppColors.surf, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
    child: Row(children: [
      Column(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: AppColors.tealLt, borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.layers_outlined, color: AppColors.teal, size: 18),
        ),
        const SizedBox(height: 6),
        Text(event.time, style: const TextStyle(fontSize: 9, color: AppColors.sub2, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Text(event.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMain))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: event.statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
            child: Text(event.status, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: event.statusColor)),
          ),
        ]),
        Text(event.client, style: const TextStyle(fontSize: 10, color: AppColors.sub)),
        Text(event.region, style: const TextStyle(fontSize: 10, color: AppColors.sub2)),
      ])),
    ]),
  );
}

class _CalEvent {
  final String name, client, region, time, status;
  final Color statusColor;
  final DateTime date;
  const _CalEvent({required this.name, required this.client, required this.region, required this.time, required this.status, required this.statusColor, required this.date});
}

class _LegendItem extends StatelessWidget {
  final String label;
  final Color color;
  const _LegendItem(this.label, this.color);

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 7, height: 7, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
    const SizedBox(width: 5),
    Text(label, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.sub)),
  ]);
}

class _WeekStat extends StatelessWidget {
  final String value, label;
  const _WeekStat(this.value, this.label);

  @override
  Widget build(BuildContext context) => Expanded(child: Column(children: [
    Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.teal)),
    Text(label, style: const TextStyle(fontSize: 9.5, color: AppColors.sub, fontWeight: FontWeight.w600)),
  ]));
}

class _CalNavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CalNavBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 30, height: 30,
      decoration: BoxDecoration(color: AppColors.tealLt, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.line)),
      child: Icon(icon, color: AppColors.teal, size: 18),
    ),
  );
}

class _MonthSumPill extends StatelessWidget {
  final String label;
  final Color bg, fg;
  const _MonthSumPill(this.label, this.bg, this.fg);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
  );
}
