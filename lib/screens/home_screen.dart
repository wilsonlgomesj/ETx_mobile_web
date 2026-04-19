import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'campaigns_screen.dart';
import 'reports_screen.dart';
import 'calendar_screen.dart';
import 'profile_screen.dart';
import 'new_camp_screen.dart';
import 'notifications_screen.dart';
import 'os_detail_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(children: [
          // Status bar
          Container(
            height: 38,
            color: AppColors.surf,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('09:34', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMain)),
              Row(children: [
                if (state.isOffline)
                  const Text('OFFLINE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.warn)),
                const SizedBox(width: 4),
                const Text('📶 🔋'),
              ]),
            ]),
          ),

          Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header
            Container(
              color: AppColors.surf,
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  RichText(text: const TextSpan(
                    children: [
                      TextSpan(text: 'EcoFlow', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textMain)),
                      TextSpan(text: 'App', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.teal)),
                    ],
                  )),
                  const Text('Gestão Ambiental de Campo', style: TextStyle(fontSize: 7, letterSpacing: 2, color: AppColors.sub2, fontWeight: FontWeight.w700)),
                ])),
                Row(children: [
                  _IconBtn(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
                    child: Stack(children: [
                      const Icon(Icons.notifications_outlined, size: 18, color: AppColors.sub),
                      if (state.notifCount > 0)
                        Positioned(top: -3, right: -3, child: Container(
                          width: 15, height: 15,
                          decoration: const BoxDecoration(color: AppColors.teal, shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: Text('${state.notifCount}', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.white)),
                        )),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  _IconBtn(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
                    child: Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(color: AppColors.tealLt, borderRadius: BorderRadius.circular(12)),
                      alignment: Alignment.center,
                      child: Text(state.userInitials, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.teal)),
                    ),
                  ),
                ]),
              ]),
            ),

            // Greeting
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('quinta-feira, 3 de abr', style: TextStyle(fontSize: 11, color: AppColors.sub)),
                RichText(text: TextSpan(
                  children: [
                    const TextSpan(text: 'Olá, ', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textMain)),
                    TextSpan(text: state.userName.split(' ').first, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.teal)),
                  ],
                )),
              ]),
            ),

            // Sync banner
            if (state.syncPending > 0)
              Container(
                margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0x14F07A2A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x40F07A2A)),
                ),
                child: Row(children: [
                  const Text('⚠️', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${state.syncPending} coletas aguardando envio', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.warn)),
                    const Text('Sincronize quando houver sinal', style: TextStyle(fontSize: 10, color: AppColors.sub)),
                  ])),
                  GestureDetector(
                    onTap: () { context.read<AppState>().doSync(); showToast(context, '✅ Dados enviados!'); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(color: AppColors.accDim, borderRadius: BorderRadius.circular(20)),
                      child: const Text('Enviar', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.teal)),
                    ),
                  ),
                ]),
              ),

            // CTA
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: GestureDetector(
                onTap: () {
                  if (state.fieldWork && state.activeCampaignId != null) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const OsDetailScreen()));
                  } else {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const NewCampScreen()));
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: state.fieldWork ? AppColors.green : AppColors.teal,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        state.fieldWork ? Icons.check_circle_outline : Icons.add_circle_outline,
                        color: Colors.white, size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        state.fieldWork ? 'Campanha em campo' : 'Iniciar coleta de campo',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      Text(
                        state.fieldWork
                          ? '${state.pendCount} pontos pendentes'
                          : '6 pontos pendentes',
                        style: const TextStyle(fontSize: 11, color: Color(0xA6FFFFFF)),
                      ),
                    ])),
                    const Text('›', style: TextStyle(fontSize: 20, color: Color(0x66FFFFFF), fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ),

            // Progress card (shown if in field)
            if (state.fieldWork) Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
              child: AppCard(child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('CAMPANHA ATIVA', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: AppColors.sub)),
                  Text('${(state.progress * 100).toInt()}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.teal)),
                ]),
                const SizedBox(height: 10),
                AppProgressBar(value: state.progress),
                const SizedBox(height: 12),
                Row(children: [
                  _ProgressStat('${state.doneCount}', 'coletados', AppColors.teal),
                  _Divider(),
                  _ProgressStat('${state.pendCount}', 'pendentes', AppColors.textMain),
                  _Divider(),
                  _ProgressStat('${state.ncCount}', 'não coletados', AppColors.sub2),
                ]),
              ])),
            ),

            // 2x2 Navigation grid
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.3,
                children: [
                  _NavCard(
                    icon: Icons.layers_outlined,
                    label: 'Campanhas',
                    sub: 'Minhas ordens de serviço',
                    teal: true,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CampaignsScreen())),
                  ),
                  _NavCard(
                    icon: Icons.bar_chart,
                    label: 'Relatórios',
                    sub: 'PDF · Excel · campo',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen())),
                  ),
                  _NavCard(
                    icon: Icons.calendar_month_outlined,
                    label: 'Calendário',
                    sub: 'Escala semanal e mensal',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CalendarScreen())),
                  ),
                  _NavCard(
                    icon: Icons.person_outline,
                    label: 'Perfil',
                    sub: 'Dados e conectividade',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
                  ),
                ],
              ),
            ),
          ]))),
        ]),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _IconBtn({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: AppColors.surf,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

class _ProgressStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _ProgressStat(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Expanded(child: Column(children: [
    Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
    Text(label, style: const TextStyle(fontSize: 8, color: AppColors.sub, letterSpacing: 0.5)),
  ]));
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(width: 1, height: 24, color: AppColors.line);
}

class _NavCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final bool teal;
  final VoidCallback? onTap;
  const _NavCard({required this.icon, required this.label, required this.sub, this.teal = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: teal ? AppColors.tealLt : AppColors.surf,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: teal ? const Color(0x4D1A8A8A) : AppColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: teal ? AppColors.teal : AppColors.sub, size: 20),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textMain)),
          const SizedBox(height: 3),
          Text(sub, style: const TextStyle(fontSize: 10, color: AppColors.sub, height: 1.4)),
        ]),
      ),
    );
  }
}
