import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class _Notif {
  final String title;
  final String sub;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final Color? borderColor;
  final Color? titleColor;
  bool read;

  _Notif({
    required this.title,
    required this.sub,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    this.borderColor,
    this.titleColor,
    this.read = false,
  });
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final List<_Notif> _notifs = [
    _Notif(
      title: '4 registros sincronizados',
      sub: 'Há 12 minutos',
      icon: Icons.cloud_done_outlined,
      iconBg: AppColors.tealLt,
      iconColor: AppColors.teal,
    ),
    _Notif(
      title: 'Campanha Cubatão atrasada',
      sub: 'Prazo expirou em 01/04/2025',
      icon: Icons.warning_amber_outlined,
      iconBg: const Color(0x14F07A2A),
      iconColor: AppColors.warn,
      borderColor: const Color(0x4DF07A2A),
      titleColor: AppColors.warn,
      read: false,
    ),
    _Notif(
      title: 'Nova campanha atribuída',
      sub: 'Vale Carajás — Campanha 1S/2025',
      icon: Icons.layers_outlined,
      iconBg: AppColors.tealLt,
      iconColor: AppColors.teal,
      read: true,
    ),
    _Notif(
      title: 'Relatório disponível para download',
      sub: 'Paulínia 03/2025 — PDF gerado',
      icon: Icons.picture_as_pdf_outlined,
      iconBg: const Color(0x14DC2626),
      iconColor: AppColors.danger,
      read: true,
    ),
  ];

  int get _unreadCount => _notifs.where((n) => !n.read).length;

  void _markAllRead() => setState(() {
    for (final n in _notifs) { n.read = true; }
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppTopBar(
        title: 'Notificações',
        subtitle: _unreadCount > 0 ? '$_unreadCount não lidas' : 'Todas lidas',
        actions: [
          if (_unreadCount > 0)
            GestureDetector(
              onTap: _markAllRead,
              child: Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.tealLt,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x401A8A8A)),
                ),
                child: const Text(
                  'Marcar todas lidas',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.teal),
                ),
              ),
            ),
        ],
      ),
      body: _notifs.isEmpty
          ? _buildEmpty()
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
              itemCount: _notifs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _NotifCard(
                notif: _notifs[i],
                onTap: () => setState(() => _notifs[i].read = true),
              ),
            ),
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(color: AppColors.tealLt, borderRadius: BorderRadius.circular(20)),
        child: const Icon(Icons.notifications_none_outlined, color: AppColors.teal, size: 30),
      ),
      const SizedBox(height: 12),
      const Text('Sem notificações', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textMain)),
      const SizedBox(height: 4),
      const Text('Você está em dia!', style: TextStyle(fontSize: 12, color: AppColors.sub)),
    ]),
  );
}

class _NotifCard extends StatelessWidget {
  final _Notif notif;
  final VoidCallback onTap;
  const _NotifCard({required this.notif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: notif.read ? AppColors.surf : AppColors.tealLt.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: notif.borderColor ?? (notif.read ? AppColors.line : const Color(0x401A8A8A)),
          ),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: notif.iconBg, borderRadius: BorderRadius.circular(10)),
            child: Icon(notif.icon, color: notif.iconColor, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              notif.title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: notif.read ? FontWeight.w500 : FontWeight.w700,
                color: notif.titleColor ?? AppColors.textMain,
              ),
            ),
            const SizedBox(height: 2),
            Text(notif.sub, style: const TextStyle(fontSize: 11, color: AppColors.sub)),
          ])),
          if (!notif.read)
            Container(
              width: 8, height: 8,
              margin: const EdgeInsets.only(top: 4),
              decoration: const BoxDecoration(color: AppColors.teal, shape: BoxShape.circle),
            ),
        ]),
      ),
    );
  }
}
