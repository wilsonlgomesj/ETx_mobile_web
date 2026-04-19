import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _roleCtrl;
  late TextEditingController _regCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _companyCtrl;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _nameCtrl    = TextEditingController(text: state.userName);
    _roleCtrl    = TextEditingController(text: state.userRole);
    _regCtrl     = TextEditingController(text: state.userReg);
    _emailCtrl   = TextEditingController(text: state.userEmail);
    _phoneCtrl   = TextEditingController(text: state.userPhone);
    _companyCtrl = TextEditingController(text: state.userCompany);
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _roleCtrl.dispose(); _regCtrl.dispose();
    _emailCtrl.dispose(); _phoneCtrl.dispose(); _companyCtrl.dispose();
    super.dispose();
  }

  void _save() {
    context.read<AppState>().updateProfile(
      name:    _nameCtrl.text.trim(),
      role:    _roleCtrl.text.trim(),
      reg:     _regCtrl.text.trim(),
      email:   _emailCtrl.text.trim(),
      phone:   _phoneCtrl.text.trim(),
      company: _companyCtrl.text.trim(),
    );
    Navigator.pop(context);
    showToast(context, '✅ Perfil atualizado!');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Container(
          height: 56,
          decoration: const BoxDecoration(
            color: AppColors.surf,
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
                child: const Icon(Icons.chevron_left, size: 22, color: AppColors.textMain),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(child: Text('Dados Pessoais', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textMain))),
            GestureDetector(
              onTap: _save,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(12)),
                child: const Text('Salvar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
      body: SingleChildScrollView(child: Column(children: [
        // Avatar section
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          color: AppColors.surf,
          child: Column(children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: AppColors.tealLt,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0x4D1A8A8A), width: 2),
              ),
              alignment: Alignment.center,
              child: Text(state.userInitials, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.teal)),
            ),
            const SizedBox(height: 10),
            const Text('Toque para alterar foto', style: TextStyle(fontSize: 11, color: AppColors.sub2)),
          ]),
        ),
        Container(height: 1, color: AppColors.line),

        // Form
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(children: [
            _PaperField(controller: _nameCtrl,  label: 'Nome completo'),
            _PaperField(controller: _roleCtrl,  label: 'Função / Cargo'),
            _PaperField(controller: _regCtrl,   label: 'Registro profissional'),
            _PaperField(controller: _emailCtrl, label: 'E-mail', keyboardType: TextInputType.emailAddress),
            _PaperField(controller: _phoneCtrl, label: 'Telefone', keyboardType: TextInputType.phone),
            _PaperField(controller: _companyCtrl, label: 'Empresa'),
            const SizedBox(height: 4),

            // Outlined cancel button
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.line, width: 1.5),
                ),
                alignment: Alignment.center,
                child: const Text('Cancelar alterações', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMain)),
              ),
            ),
            const SizedBox(height: 40),
          ]),
        ),
      ])),
    );
  }
}

// ── PAPER-STYLE TEXT FIELD ────────────────────────────────────
class _PaperField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  const _PaperField({required this.controller, required this.label, this.keyboardType});

  @override
  State<_PaperField> createState() => _PaperFieldState();
}

class _PaperFieldState extends State<_PaperField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Stack(children: [
        Focus(
          onFocusChange: (f) => setState(() => _focused = f),
          child: TextField(
            controller: widget.controller,
            keyboardType: widget.keyboardType,
            style: const TextStyle(fontSize: 14, color: AppColors.textMain),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surf,
              labelText: widget.label,
              labelStyle: TextStyle(
                fontSize: _focused ? 11 : 14,
                color: _focused ? AppColors.teal : AppColors.sub,
                fontWeight: _focused ? FontWeight.w600 : FontWeight.w400,
              ),
              floatingLabelBehavior: FloatingLabelBehavior.auto,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: AppColors.line, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: AppColors.line, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: AppColors.teal, width: 2),
              ),
              contentPadding: const EdgeInsets.fromLTRB(14, 18, 14, 8),
            ),
          ),
        ),
      ]),
    );
  }
}
