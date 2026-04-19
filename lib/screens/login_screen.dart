import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../api/auth_service.dart';
import '../api/api_exceptions.dart';
import '../sync/sync_service.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LOGIN SCREEN
// Shown when AuthService has no valid session. After successful login, we
// also kick off a first sync so the technician immediately sees any newly
// assigned campaigns pushed from the web.
// ─────────────────────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey      = GlobalKey<FormState>();

  bool _obscure = true;
  bool _loading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      await AuthService.instance.login(
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
      );

      if (!mounted) return;

      // Hidrata o AppState com o perfil recém-logado e dispara sync inicial.
      final state = context.read<AppState>();
      final session = AuthService.instance.session!;
      state.updateProfile(name: session.userName, email: session.userEmail);

      // ignore: discarded_futures
      SyncService.instance.syncNow();

      Navigator.of(context).pushReplacementNamed('/home');
    } on UnauthorizedException {
      if (!mounted) return;
      setState(() => _errorMessage = 'E-mail ou senha incorretos.');
    } on NetworkException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Erro inesperado: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    _brand(),
                    const SizedBox(height: 32),
                    _headline(),
                    const SizedBox(height: 24),
                    _emailField(),
                    const SizedBox(height: 14),
                    _passwordField(),
                    const SizedBox(height: 8),
                    if (_errorMessage != null) _errorBanner(),
                    const SizedBox(height: 16),
                    _submitButton(),
                    const SizedBox(height: 24),
                    _footer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _brand() => Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.teal.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.water_drop_outlined,
                color: AppColors.teal, size: 32),
          ),
          const SizedBox(height: 12),
          const Text(
            'EcoFlow',
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textMain),
          ),
          const Text(
            'Módulo Campo · Monitoramento Ambiental',
            style: TextStyle(fontSize: 13, color: AppColors.sub),
          ),
        ],
      );

  Widget _headline() => const Text(
        'Entrar',
        style: TextStyle(
            fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.textMain),
        textAlign: TextAlign.center,
      );

  Widget _emailField() => TextFormField(
        controller: _emailCtrl,
        enabled: !_loading,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'E-mail',
          prefixIcon: Icon(Icons.mail_outline),
          border: OutlineInputBorder(),
        ),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'Informe seu e-mail';
          if (!v.contains('@')) return 'E-mail inválido';
          return null;
        },
      );

  Widget _passwordField() => TextFormField(
        controller: _passwordCtrl,
        enabled: !_loading,
        obscureText: _obscure,
        autofillHints: const [AutofillHints.password],
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'Senha',
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
          border: const OutlineInputBorder(),
        ),
        validator: (v) {
          if (v == null || v.isEmpty) return 'Informe sua senha';
          if (v.length < 4) return 'Senha muito curta';
          return null;
        },
      );

  Widget _errorBanner() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 13)),
          ),
        ]),
      );

  Widget _submitButton() => SizedBox(
        height: 48,
        child: ElevatedButton(
          onPressed: _loading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.teal,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Entrar',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      );

  Widget _footer() => const Column(
        children: [
          Text(
            'Para acessar, solicite suas credenciais ao gestor\nda operação de campo.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.sub),
          ),
        ],
      );
}
