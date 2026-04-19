import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ── PILL BADGE ──────────────────────────────────────────────
enum PillVariant { teal, warn, danger, neutral, green }

class PillBadge extends StatelessWidget {
  final String text;
  final PillVariant variant;
  const PillBadge(this.text, {super.key, this.variant = PillVariant.teal});

  @override
  Widget build(BuildContext context) {
    Color bg; Color fg;
    switch (variant) {
      case PillVariant.teal:    bg = AppColors.tealLt; fg = AppColors.teal; break;
      case PillVariant.warn:    bg = const Color(0x1EF07A2A); fg = AppColors.warn; break;
      case PillVariant.danger:  bg = const Color(0x14DC2626); fg = AppColors.danger; break;
      case PillVariant.neutral: bg = AppColors.raised; fg = AppColors.sub; break;
      case PillVariant.green:   bg = const Color(0x1A16A34A); fg = AppColors.green; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: fg, letterSpacing: 0.3)),
    );
  }
}

// ── STATUS DOT PILL ──────────────────────────────────────────
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  const StatusPill({super.key, required this.label, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 5, height: 5, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}

// ── PROGRESS BAR ─────────────────────────────────────────────
class AppProgressBar extends StatelessWidget {
  final double value; // 0.0–1.0
  final Color? color;
  const AppProgressBar({super.key, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 4,
      decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4)),
      child: FractionallySizedBox(
        widthFactor: value.clamp(0.0, 1.0),
        alignment: Alignment.centerLeft,
        child: Container(
          decoration: BoxDecoration(
            color: color ?? AppColors.teal,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

// ── APP CARD ─────────────────────────────────────────────────
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? borderColor;
  final Color? color;
  final VoidCallback? onTap;
  const AppCard({super.key, required this.child, this.padding, this.borderColor, this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: padding ?? const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color ?? AppColors.surf,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor ?? AppColors.line),
        ),
        child: child,
      ),
    );
  }
}

// ── SECTION HEADER ───────────────────────────────────────────
class SectionHeader extends StatelessWidget {
  final String text;
  final EdgeInsets? padding;
  const SectionHeader(this.text, {super.key, this.padding});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(24, 14, 24, 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: AppColors.sub),
      ),
    );
  }
}

// ── TOP BAR ──────────────────────────────────────────────────
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  const AppTopBar({super.key, required this.title, this.subtitle, this.actions});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: AppColors.surf,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.line),
            ),
            child: const Icon(Icons.chevron_left, size: 22, color: AppColors.textMain),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textMain)),
            if (subtitle != null)
              Text(subtitle!, style: const TextStyle(fontSize: 11, color: AppColors.sub)),
          ],
        )),
        if (actions != null) ...actions!,
      ]),
    );
  }
}

// ── TEAL CTA BUTTON ──────────────────────────────────────────
class TealButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  const TealButton({super.key, required this.label, this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color ?? AppColors.teal,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    );
  }
}

// ── TOGGLE SWITCH ─────────────────────────────────────────────
class AppToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color activeColor;
  const AppToggle({super.key, required this.value, required this.onChanged, this.activeColor = AppColors.teal});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44, height: 24,
        decoration: BoxDecoration(
          color: value ? activeColor : AppColors.line,
          borderRadius: BorderRadius.circular(12),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(3),
            width: 18, height: 18,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

// ── ICON BOX ─────────────────────────────────────────────────
class IconBox extends StatelessWidget {
  final IconData icon;
  final Color bg;
  final Color iconColor;
  final double size;
  const IconBox({super.key, required this.icon, required this.bg, required this.iconColor, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.3)),
      child: Icon(icon, color: iconColor, size: size * 0.45),
    );
  }
}

// ── MAIN APP TAB BAR ─────────────────────────────────────────
class MainTabBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  const MainTabBar({super.key, required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _TabItem(icon: Icons.home_outlined, label: 'Início'),
      _TabItem(icon: Icons.layers_outlined, label: 'Campanhas'),
      _TabItem(icon: Icons.bar_chart, label: 'Relatórios'),
      _TabItem(icon: Icons.calendar_month_outlined, label: 'Calendário'),
      _TabItem(icon: Icons.person_outline, label: 'Perfil'),
    ];
    return Container(
      height: 72,
      decoration: const BoxDecoration(
        color: AppColors.surf,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(tabs.length, (i) {
          final active = i == currentIndex;
          return GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(tabs[i].icon, size: 22, color: active ? AppColors.teal : AppColors.sub2),
                const SizedBox(height: 3),
                Text(
                  tabs[i].label,
                  style: TextStyle(
                    fontSize: 8, fontWeight: FontWeight.w700,
                    letterSpacing: 0.5, color: active ? AppColors.teal : AppColors.sub2,
                  ),
                ),
              ]),
            ),
          );
        }),
      ),
    );
  }
}

class _TabItem {
  final IconData icon;
  final String label;
  const _TabItem({required this.icon, required this.label});
}

// ── TOAST / SNACKBAR HELPER ───────────────────────────────────
void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
    backgroundColor: AppColors.textMain,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    duration: const Duration(seconds: 2),
  ));
}

// ── CHECKLIST ITEM ────────────────────────────────────────────
class ChecklistItem extends StatelessWidget {
  final String label;
  final bool checked;
  final VoidCallback onTap;
  final bool isRequired;
  const ChecklistItem({super.key, required this.label, required this.checked, required this.onTap, this.isRequired = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: checked ? AppColors.teal : AppColors.bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: checked ? AppColors.teal : AppColors.line, width: 1.5),
            ),
            child: checked ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMain))),
          if (isRequired)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0x1AF07A2A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x33F07A2A)),
              ),
              child: const Text('Obrigatório', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.warn)),
            ),
        ]),
      ),
    );
  }
}
