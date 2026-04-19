import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'edit_profile_screen.dart';
import 'campaigns_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(child: Column(children: [
        Expanded(child: SingleChildScrollView(child: Column(children: [

          // Hero banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 52),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment(0.6, 1),
                colors: [AppColors.tealDk, AppColors.teal, Color(0xFF2ACFCF)],
              ),
            ),
            child: Stack(children: [
              // Grid overlay
              Positioned.fill(child: Opacity(opacity: 0.06, child: CustomPaint(
                painter: _GridPainter(),
                child: const SizedBox.expand(),
              ))),

              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                // Avatar
                Stack(children: [
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen())),
                    child: Container(
                      width: 76, height: 76,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2.5),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 16, offset: const Offset(0,4))],
                      ),
                      alignment: Alignment.center,
                      child: Text(state.userInitials, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                  ),
                  Positioned(bottom: -4, right: -4, child: Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      color: AppColors.surf,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0x4D1A8A8A)),
                    ),
                    alignment: Alignment.center,
                    child: const Text('✏️', style: TextStyle(fontSize: 11)),
                  )),
                ]),
                const SizedBox(width: 16),

                // Name / role / reg
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(state.userName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                  Text('${state.userRole} · ${state.userCompany}', style: const TextStyle(fontSize: 11, color: Color(0xBFFFFFFF))),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.work_outline, size: 10, color: Color(0xE6FFFFFF)),
                      const SizedBox(width: 5),
                      Text(state.userReg, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xE6FFFFFF))),
                    ]),
                  ),
                ])),
              ]),
            ]),
          ),

          // Connectivity card
          Container(
            margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            decoration: BoxDecoration(color: AppColors.surf, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
            child: Column(children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('CONECTIVIDADE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: AppColors.sub)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: state.isOffline ? const Color(0x1AF07A2A) : const Color(0x1A00B87A),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(color: state.isOffline ? AppColors.warn : const Color(0xFF00FFB2), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        state.isOffline ? 'Offline' : 'Online',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: state.isOffline ? AppColors.warn : const Color(0xFF00B87A)),
                      ),
                    ]),
                  ),
                ]),
              ),

              // Network row
              _ConnRow(
                icon: Icons.wifi,
                iconBg: const Color(0x1A00B87A),
                iconColor: const Color(0xFF00B87A),
                title: 'Rede do dispositivo',
                subtitle: state.isOffline ? 'Modo offline ativo' : 'Conectado · 4G',
              ),

              // Offline toggle row
              _ConnRow(
                icon: Icons.wifi_off_outlined,
                iconBg: AppColors.raised,
                iconColor: AppColors.sub,
                title: 'Modo offline forçado',
                subtitle: state.isOffline ? 'Ativo' : 'Inativo',
                trailing: AppToggle(value: state.isOffline, onChanged: (_) => context.read<AppState>().toggleOffline()),
              ),

              // Sync queue row
              _ConnRow(
                icon: Icons.sync_outlined,
                iconBg: const Color(0x1A00B87A),
                iconColor: const Color(0xFF00B87A),
                title: 'Fila de sincronização',
                subtitle: state.syncPending > 0 ? '${state.syncPending} itens aguardando' : 'Nenhuma pendência',
                trailing: state.syncPending > 0 ? GestureDetector(
                  onTap: () { context.read<AppState>().doSync(); showToast(context, '✅ Dados enviados!'); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: AppColors.accDim, borderRadius: BorderRadius.circular(20)),
                    child: const Text('Enviar', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.teal)),
                  ),
                ) : null,
                last: true,
              ),

              if (state.isOffline && state.syncPending > 0)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0x14F07A2A), borderRadius: BorderRadius.circular(8)),
                  child: const Text('⚠ Pendências de envio detectadas. Desative o modo offline para sincronizar.', style: TextStyle(fontSize: 11, color: AppColors.warn, height: 1.5)),
                ),
            ]),
          ),

          // Account settings
          _SettingsGroup(title: 'Conta', rows: [
            _SettingRow(
              icon: Icons.person_outline,
              iconBg: AppColors.tealLt,
              iconColor: AppColors.teal,
              label: 'Dados pessoais',
              trailing: state.userName,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen())),
            ),
            _SettingRow(
              icon: Icons.layers_outlined,
              iconBg: AppColors.tealLt,
              iconColor: AppColors.teal,
              label: 'Minhas campanhas',
              trailing: '3 ativas',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CampaignsScreen())),
            ),
          ]),

          // Preferences settings
          _SettingsGroup(title: 'Preferências', rows: [
            _SettingRow(
              icon: Icons.light_mode_outlined,
              iconBg: const Color(0x146366F1),
              iconColor: const Color(0xFF6366F1),
              label: 'Tema',
              trailing: 'Claro',
              onTap: () {},
            ),
            _SettingRow(
              icon: Icons.tune_outlined,
              iconBg: const Color(0x14F59E0B),
              iconColor: const Color(0xFFD97706),
              label: 'Unidades de medida',
              trailing: state.units,
              onTap: () => context.read<AppState>().toggleUnits(),
            ),
          ]),

          // Session settings
          _SettingsGroup(title: 'Sessão', rows: [
            _SettingRow(
              icon: Icons.logout,
              iconBg: const Color(0x14DC2626),
              iconColor: AppColors.danger,
              label: 'Sair da conta',
              labelColor: AppColors.danger,
              onTap: () => _confirmSignOut(context),
            ),
          ]),

          const SizedBox(height: 88),
        ]))),
      ])),
      bottomNavigationBar: MainTabBar(currentIndex: 4, onTap: (i) => _handleTab(context, i)),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(context: context, builder: (dialogCtx) => AlertDialog(
      title: const Text('Sair da conta?'),
      content: const Text('Dados ainda não sincronizados serão mantidos localmente e enviados no próximo login.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancelar')),
        TextButton(
          onPressed: () async {
            Navigator.pop(dialogCtx);
            await context.read<AppState>().logout();
            if (!context.mounted) return;
            showToast(context, 'Sessão encerrada');
            Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
          },
          child: const Text('Sair', style: TextStyle(color: AppColors.danger)),
        ),
      ],
    ));
  }

  void _handleTab(BuildContext context, int i) {
    switch (i) {
      case 0: Navigator.of(context).popUntil((r) => r.isFirst); break;
      case 1: Navigator.of(context).pushNamed('/campaigns'); break;
      case 2: Navigator.of(context).pushNamed('/reports'); break;
      case 3: Navigator.of(context).pushNamed('/calendar'); break;
      case 4: break;
    }
  }
}

class _ConnRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg, iconColor;
  final String title, subtitle;
  final Widget? trailing;
  final bool last;
  const _ConnRow({required this.icon, required this.iconBg, required this.iconColor, required this.title, required this.subtitle, this.trailing, this.last = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
    decoration: BoxDecoration(border: Border(bottom: last ? BorderSide.none : const BorderSide(color: AppColors.line2))),
    child: Row(children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: iconColor, size: 15),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 13, color: AppColors.textMain, fontWeight: FontWeight.w600)),
        Text(subtitle, style: const TextStyle(fontSize: 10, color: AppColors.sub)),
      ])),
      if (trailing != null) trailing!,
    ]),
  );
}

class _SettingsGroup extends StatelessWidget {
  final String title;
  final List<_SettingRow> rows;
  const _SettingsGroup({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
    clipBehavior: Clip.hardEdge,
    decoration: BoxDecoration(color: AppColors.surf, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        color: AppColors.bg,
        child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: AppColors.sub)),
      ),
      Container(height: 1, color: AppColors.line),
      ...rows,
    ]),
  );
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg, iconColor;
  final String label;
  final Color? labelColor;
  final String? trailing;
  final VoidCallback? onTap;
  const _SettingRow({required this.icon, required this.iconBg, required this.iconColor, required this.label, this.labelColor, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line2))),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: iconColor, size: 15),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: labelColor ?? AppColors.textMain, fontWeight: FontWeight.w500))),
        if (trailing != null) Text(trailing!, style: const TextStyle(fontSize: 11, color: AppColors.sub)),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right, size: 16, color: labelColor ?? AppColors.sub2),
      ]),
    ),
  );
}

// ── GRID PAINTER ──────────────────────────────────────────────
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1;
    const step = 24.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}
