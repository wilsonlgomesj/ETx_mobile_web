import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../app_state.dart';
import '../database/database_helper.dart';
import '../models.dart';
import '../providers/collect_provider.dart';
import '../stabilization/stabilization_config.dart';
import '../stabilization/stabilization_models.dart';
import '../stabilization/stabilization_service.dart';
import '../sync/evidence_uploader.dart';
import '../sync/photo_capture_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'finish_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// COLLECT SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class CollectScreen extends StatefulWidget {
  const CollectScreen({super.key});

  @override
  State<CollectScreen> createState() => _CollectScreenState();
}

class _CollectScreenState extends State<CollectScreen> {
  final List<bool>   _checklistItems  = List.filled(4, false);
  final List<String> _climateSelected = [];
  final List<String?> _capturedPhotoPaths = List.filled(3, null);
  final List<String> _obsTagsSelected = [];
  final _obsController = TextEditingController();

  bool _gpsCapturing = false;
  bool _gpsCaptured  = false;
  String _gpsLat = '';
  String _gpsLng = '';

  late List<Parameter> _params;
  CollectProvider? _collectProvider;

  static const _checklistLabels = [
    'Equipamentos calibrados e testados',
    'EPI completo utilizado',
    'Protocolo POP revisado',
    'Localização GPS conferida',
  ];
  static const _photoLabels = [
    'Panorâmica geral',
    'Vista do ponto de coleta',
    'Equipamento em uso',
  ];

  @override
  void initState() {
    super.initState();
    _params = buildDefaultParams();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initCollectProvider());
  }

  void _initCollectProvider() {
    if (!mounted) return;
    final state = context.read<AppState>();
    final point = state.points[state.currentPointIndex];
    _collectProvider = CollectProvider(
      point:          point,
      collectionType: point.type.name,
    );
    _collectProvider!.addListener(_onProviderChanged);
    _collectProvider!.loadExistingReadings();
  }

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _collectProvider?.removeListener(_onProviderChanged);
    _collectProvider?.dispose();
    _obsController.dispose();
    super.dispose();
  }

  // ── HELPERS ────────────────────────────────────────────────────────────────

  bool _isPhotoCaptured(int i) => _capturedPhotoPaths[i] != null;

  Future<void> _capturePhoto(int i) async {
    final choice = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Câmera'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Galeria'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (choice == null || !mounted) return;

    final photo = choice == ImageSource.camera
        ? await PhotoCaptureService.instance.fromCamera()
        : await PhotoCaptureService.instance.fromGallery();

    if (photo == null || !mounted) return;
    setState(() => _capturedPhotoPaths[i] = photo.path);
  }

  Future<void> _uploadCapturedPhotos(AppState state, int idx) async {
    final campId = state.activeCampaignId;
    if (campId == null) return;
    final point = state.points[idx];

    final ids = await DatabaseHelper.instance.ensurePointExternalIds(
      campId, point.code, () => const Uuid().v4(),
    );
    final pointRow = await DatabaseHelper.instance.getPointRaw(campId, point.code);
    final fieldPointId = pointRow?['id'] as int?;

    for (int i = 0; i < _capturedPhotoPaths.length; i++) {
      final path = _capturedPhotoPaths[i];
      if (path == null) continue;
      try {
        await EvidenceUploader.instance.uploadAndRegister(
          localPath:        path,
          externalId:       const Uuid().v4(),
          recordExternalId: ids.recordExternalId,
          pointExternalId:  ids.pointExternalId,
          fieldPointId:     fieldPointId,
          capturedAt:       DateTime.now(),
          caption:          _photoLabels[i],
        );
      } catch (_) {
        // Evidence row is registered locally as 'pending'; will retry when online.
      }
    }
  }

  Future<void> _captureGps() async {
    setState(() => _gpsCapturing = true);
    try {
      // Check / request permission.
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          showToast(context, '⚠ Permissão de localização negada');
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );

      if (!mounted) return;
      setState(() {
        _gpsCaptured = true;
        _gpsLat = pos.latitude.toStringAsFixed(6);
        _gpsLng = pos.longitude.toStringAsFixed(6);
      });
    } on LocationServiceDisabledException {
      if (mounted) showToast(context, '⚠ Ative o GPS do dispositivo');
    } catch (e) {
      if (mounted) showToast(context, '⚠ Erro ao capturar GPS: $e');
    } finally {
      if (mounted) setState(() => _gpsCapturing = false);
    }
  }

  // ── SAVE FLOW ───────────────────────────────────────────────────────────────

  void _trySave() {
    final cp = _collectProvider;

    // If the provider has no stabilization params (e.g. piezômetro),
    // or all required params are already satisfied → save directly.
    if (cp == null || !cp.hasStabilizationParams || cp.allRequiredSatisfied) {
      _executeSave();
      return;
    }

    // Some required params are not stabilized — open the exception modal.
    _showExceptionModal(cp.unsatisfiedRequired, onAllJustified: _executeSave);
  }

  Future<void> _executeSave() async {
    final state = context.read<AppState>();
    final idx   = state.currentPointIndex;

    // Persist stabilization summary before marking point done
    await _collectProvider?.saveStabilizationSummary();

    // Propagate final stabilized values back into _params so AppState sees them
    if (_collectProvider != null) {
      for (final entry in _collectProvider!.stabStates.entries) {
        final finalVal = entry.value.lastResult?.finalValue;
        if (finalVal == null) continue;
        final pi = _params.indexWhere((p) => p.label == entry.key);
        if (pi >= 0) _params[pi].value = finalVal.toStringAsFixed(2);
        state.setPointParam(idx, entry.key, finalVal.toStringAsFixed(2));
      }
    }

    await state.markPointDone(idx);
    if (_gpsCaptured) await state.setPointGps(idx, _gpsLat, _gpsLng);

    // Upload captured photos in background — failures are stored locally and
    // retried automatically by EvidenceUploader.retryFailedUploads().
    unawaited(_uploadCapturedPhotos(state, idx));

    if (!mounted) return;
    Navigator.pop(context);
    if (state.progress >= 1.0) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const FinishScreen()));
    } else {
      showToast(context, '✅ Ponto salvo!');
    }
  }

  void _reportNc() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NcModal(
        onConfirm: (motive) {
          final state = context.read<AppState>();
          state.markPointNc(state.currentPointIndex, motive);
          Navigator.pop(context);
          Navigator.pop(context);
        },
      ),
    );
  }

  // ── EXCEPTION MODAL ─────────────────────────────────────────────────────────

  void _showExceptionModal(
    List<String> params, {
    required VoidCallback onAllJustified,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StabExceptionModal(
        paramNames: params,
        collectProvider: _collectProvider!,
        onConfirm: () {
          Navigator.pop(context);
          onAllJustified();
        },
      ),
    );
  }

  // ── BUILD ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final point = state.points[state.currentPointIndex];

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppTopBar(title: 'Coleta de Ponto', subtitle: point.code),
      body: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Checklist pré-campo ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
            child: AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('CHECKLIST PRÉ-CAMPO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppColors.sub)),
              const SizedBox(height: 10),
              ...List.generate(_checklistLabels.length, (i) => ChecklistItem(
                label:      _checklistLabels[i],
                checked:    _checklistItems[i],
                isRequired: i < 2,
                onTap:      () => setState(() => _checklistItems[i] = !_checklistItems[i]),
              )),
            ])),
          ),

          // ── Cabeçalho do ponto ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
            child: AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.tealLt, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0x401A8A8A))),
                  child: Text(point.code, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.teal, letterSpacing: 1.5)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.raised, borderRadius: BorderRadius.circular(20)),
                  child: Text(point.typeLabel, style: const TextStyle(fontSize: 11, color: AppColors.sub)),
                ),
              ]),
              const SizedBox(height: 8),
              Text(point.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textMain)),
              const SizedBox(height: 4),
              const Text('Ponto de monitoramento ambiental com coleta de parâmetros in situ.', style: TextStyle(fontSize: 12, color: AppColors.sub, height: 1.5)),
            ])),
          ),

          // ── GPS ────────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surf,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _gpsCaptured ? const Color(0x591A8A8A) : AppColors.line),
              ),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('GPS / LOCALIZAÇÃO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppColors.sub)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _gpsCaptured ? AppColors.tealLt : const Color(0x1AF07A2A),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _gpsCaptured ? '✓ Capturado' : 'Aguardando',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _gpsCaptured ? AppColors.teal : AppColors.warn),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                if (_gpsCaptured)
                  Row(children: [
                    Expanded(child: Column(children: [
                      Text(_gpsLat, style: const TextStyle(fontSize: 12, color: AppColors.textMain, fontWeight: FontWeight.w500)),
                      const Text('LATITUDE', style: TextStyle(fontSize: 8, color: AppColors.sub, letterSpacing: 0.5)),
                    ])),
                    Expanded(child: Column(children: [
                      Text(_gpsLng, style: const TextStyle(fontSize: 12, color: AppColors.textMain, fontWeight: FontWeight.w500)),
                      const Text('LONGITUDE', style: TextStyle(fontSize: 8, color: AppColors.sub, letterSpacing: 0.5)),
                    ])),
                  ])
                else
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0x14F07A2A), borderRadius: BorderRadius.circular(8)),
                    child: const Text('⚠ GPS aguardando sinal. Certifique-se que o GPS está ativo.', style: TextStyle(fontSize: 10, color: AppColors.warn, height: 1.5)),
                  ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _gpsCaptured ? null : _captureGps,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _gpsCaptured ? AppColors.teal : AppColors.tealLt,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _gpsCaptured ? AppColors.teal : const Color(0x401A8A8A)),
                    ),
                    alignment: Alignment.center,
                    child: _gpsCapturing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal))
                        : Text(
                            _gpsCaptured ? '✓ Capturado' : 'Capturar GPS',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _gpsCaptured ? Colors.white : AppColors.teal),
                          ),
                  ),
                ),
              ]),
            ),
          ),

          // ── Condições climáticas ───────────────────────────────────────────
          const SectionHeader('Condições Climáticas'),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
            child: Wrap(spacing: 6, runSpacing: 6, children: kClimateOptions.map((opt) {
              final active = _climateSelected.contains(opt);
              return GestureDetector(
                onTap: () => setState(() {
                  active ? _climateSelected.remove(opt) : _climateSelected.add(opt);
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                    color: active ? AppColors.tealLt : AppColors.surf,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: active ? const Color(0x4D1A8A8A) : AppColors.line),
                  ),
                  child: Text(opt, style: TextStyle(fontSize: 11, color: active ? AppColors.teal : AppColors.sub)),
                ),
              );
            }).toList()),
          ),

          // ── Parâmetros ────────────────────────────────────────────────────
          const SectionHeader('Parâmetros Coletados'),
          Container(
            margin: const EdgeInsets.fromLTRB(0, 0, 0, 14),
            decoration: const BoxDecoration(
              color: AppColors.surf,
              border: Border.symmetric(horizontal: BorderSide(color: AppColors.line)),
            ),
            child: Column(
              children: _params.map((p) {
                final stabState = _collectProvider?.stateFor(p.label);
                if (stabState != null) {
                  return _StabParamSection(
                    param:       p,
                    stabState:   stabState,
                    onAddReading:    (val) => _collectProvider!.addReading(p.label, val),
                    onRemoveLast:    ()    => _collectProvider!.removeLastReading(p.label),
                  );
                }
                return _ParamRow(param: p);
              }).toList(),
            ),
          ),

          // ── Evidências fotográficas ────────────────────────────────────────
          const SectionHeader('Evidências Fotográficas'),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Row(children: List.generate(3, (i) => Expanded(child: GestureDetector(
              onTap: () => _capturePhoto(i),
              child: Container(
                margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                height: 90,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: _isPhotoCaptured(i) ? AppColors.tealLt : AppColors.surf,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _isPhotoCaptured(i) ? const Color(0x591A8A8A) : AppColors.line,
                      width: 1.5),
                ),
                child: _isPhotoCaptured(i)
                    ? Stack(fit: StackFit.expand, children: [
                        Image.file(File(_capturedPhotoPaths[i]!), fit: BoxFit.cover),
                        Positioned(
                          bottom: 0, left: 0, right: 0,
                          child: Container(
                            color: const Color(0x881A8A8A),
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(_photoLabels[i],
                                style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.w600),
                                textAlign: TextAlign.center),
                          ),
                        ),
                      ])
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.camera_alt_outlined, size: 22, color: AppColors.sub2),
                        const SizedBox(height: 4),
                        Text(_photoLabels[i],
                            style: const TextStyle(fontSize: 9, color: AppColors.sub, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center),
                      ]),
              ),
            )))),
          ),

          // ── Observações ───────────────────────────────────────────────────
          const SectionHeader('Observações'),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('TAGS RÁPIDAS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.sub2, letterSpacing: 1)),
              const SizedBox(height: 6),
              Wrap(spacing: 5, runSpacing: 5, children: kObsTags.map((tag) {
                final active = _obsTagsSelected.contains(tag);
                return GestureDetector(
                  onTap: () => setState(() => active ? _obsTagsSelected.remove(tag) : _obsTagsSelected.add(tag)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: active ? AppColors.tealLt : AppColors.surf,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: active ? const Color(0x4D1A8A8A) : AppColors.line),
                    ),
                    child: Text(tag, style: TextStyle(fontSize: 11, color: active ? AppColors.teal : AppColors.sub)),
                  ),
                );
              }).toList()),
              const SizedBox(height: 8),
              TextField(
                controller: _obsController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Observações gerais do ponto (odor, coloração, fauna, etc.)…',
                  hintStyle: const TextStyle(fontSize: 12, color: AppColors.sub2),
                  filled: true, fillColor: AppColors.surf,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.teal)),
                  contentPadding: const EdgeInsets.all(10),
                ),
              ),
            ]),
          ),

          // ── Cadeia de custódia ────────────────────────────────────────────
          const SectionHeader('Cadeia de Custódia'),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
            child: Column(children: [
              Row(children: [
                Expanded(child: _CustodyField(label: 'N° Frasco',     hint: 'Ex: FA-2025-001')),
                const SizedBox(width: 8),
                Expanded(child: _CustodyField(label: 'Preservante',   hint: 'Ex: HNO₃')),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _CustodyField(label: 'Laboratório',   hint: 'Ex: Labágua SP')),
                const SizedBox(width: 8),
                Expanded(child: _CustodyField(label: 'Temp. Conservação', hint: 'Ex: 4°C')),
              ]),
            ]),
          ),

          // ── Save button ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: TealButton(label: '💾 Salvar coleta do ponto', onTap: _trySave),
          ),

          // ── NC button ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: GestureDetector(
              onTap: _reportNc,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0x12DC2626),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x2EDC2626)),
                ),
                child: const Column(children: [
                  Text('⚠ Registrar Não Conformidade', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.danger)),
                  SizedBox(height: 2),
                  Text('Ponto inacessível, seco ou com impedimento', style: TextStyle(fontSize: 10, color: Color(0x99DC2626))),
                ]),
              ),
            ),
          ),

          const SizedBox(height: 40),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STABILIZATION PARAMETER SECTION
// Replaces the simple _ParamRow for params that require stabilization.
// ─────────────────────────────────────────────────────────────────────────────

class _StabParamSection extends StatefulWidget {
  final Parameter param;
  final ParameterStabilizationState stabState;
  final Future<void> Function(double) onAddReading;
  final Future<void> Function() onRemoveLast;

  const _StabParamSection({
    required this.param,
    required this.stabState,
    required this.onAddReading,
    required this.onRemoveLast,
  });

  @override
  State<_StabParamSection> createState() => _StabParamSectionState();
}

class _StabParamSectionState extends State<_StabParamSection> {
  final _inputCtrl = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _addReading() async {
    final raw = _inputCtrl.text.trim().replaceAll(',', '.');
    final val = double.tryParse(raw);
    if (val == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valor inválido'), duration: Duration(seconds: 1)),
      );
      return;
    }
    setState(() => _adding = true);
    await widget.onAddReading(val);
    _inputCtrl.clear();
    if (mounted) setState(() => _adding = false);
  }

  // ── Status chip colors ────────────────────────────────────────────────────

  static Color _bgColor(StabStatus s) {
    switch (s) {
      case StabStatus.waiting:           return const Color(0xFFF0F4F4);
      case StabStatus.collecting:        return const Color(0xFFFFF3E0);
      case StabStatus.stabilized:        return const Color(0xFFE8F5E9);
      case StabStatus.outOfRange:        return const Color(0xFFFFEBEE);
      case StabStatus.justifiedException:return const Color(0xFFF3E5F5);
    }
  }

  static Color _fgColor(StabStatus s) {
    switch (s) {
      case StabStatus.waiting:           return AppColors.sub;
      case StabStatus.collecting:        return AppColors.warn;
      case StabStatus.stabilized:        return AppColors.green;
      case StabStatus.outOfRange:        return AppColors.danger;
      case StabStatus.justifiedException:return const Color(0xFF7B1FA2);
    }
  }

  static Color _borderColor(StabStatus s) {
    switch (s) {
      case StabStatus.waiting:           return AppColors.line;
      case StabStatus.collecting:        return const Color(0x40F07A2A);
      case StabStatus.stabilized:        return const Color(0x4016A34A);
      case StabStatus.outOfRange:        return const Color(0x40DC2626);
      case StabStatus.justifiedException:return const Color(0x407B1FA2);
    }
  }

  static String _statusLabel(StabStatus s) {
    switch (s) {
      case StabStatus.waiting:           return 'Aguardando';
      case StabStatus.collecting:        return 'Coletando';
      case StabStatus.stabilized:        return 'Estabilizado ✓';
      case StabStatus.outOfRange:        return 'Fora do critério';
      case StabStatus.justifiedException:return 'Exceção justificada';
    }
  }

  @override
  Widget build(BuildContext context) {
    final s      = widget.stabState;
    final status = s.effectiveStatus;
    final rule   = s.rule;
    final readings = s.readings;
    final result   = s.lastResult;

    return Container(
      decoration: BoxDecoration(
        color: widget.param.isPre ? const Color(0x07F07A2A) : AppColors.surf,
        border: Border(
          bottom: const BorderSide(color: AppColors.line2),
          left: BorderSide(color: _borderColor(status), width: 3),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header row: label + status chip ─────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(rule.parameterName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMain)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color:        _bgColor(status),
                borderRadius: BorderRadius.circular(20),
                border:       Border.all(color: _borderColor(status)),
              ),
              child: Text(_statusLabel(status), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _fgColor(status))),
            ),
          ]),
        ),

        // ── Criterion label ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 3, 14, 8),
          child: Text(
            StabilizationService.criterionLabel(rule),
            style: const TextStyle(fontSize: 10, color: AppColors.sub2),
          ),
        ),

        // ── Reading chips ────────────────────────────────────────────────────
        if (readings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              for (int i = 0; i < readings.length; i++)
                _ReadingChip(
                  index:         i,
                  reading:       readings[i],
                  isLast:        i == readings.length - 1,
                  fgColor:       _fgColor(status),
                ),
            ]),
          ),

        // ── Message from service ─────────────────────────────────────────────
        if (result != null && result.status != StabStatus.stabilized)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
            child: Text(result.message, style: TextStyle(fontSize: 10, color: _fgColor(status))),
          ),

        // ── Final value display when stabilized ──────────────────────────────
        if (status == StabStatus.stabilized && result?.finalValue != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Row(children: [
              Text(
                result!.finalValue!.toStringAsFixed(2),
                style: const TextStyle(fontSize: 22, color: AppColors.green, fontWeight: FontWeight.w700, fontFamily: 'monospace'),
              ),
              const SizedBox(width: 6),
              Text(rule.unit, style: const TextStyle(fontSize: 10, color: AppColors.sub2)),
              const SizedBox(width: 8),
              if (widget.param.previousValue != null)
                Text('ant. ${widget.param.previousValue}', style: const TextStyle(fontSize: 10, color: AppColors.sub)),
            ]),
          ),

        // ── Exception badge ──────────────────────────────────────────────────
        if (status == StabStatus.justifiedException && s.exception != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0x0F7B1FA2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0x307B1FA2)),
              ),
              child: Text(
                '📋 ${s.exception!.predefinedReason}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF7B1FA2)),
              ),
            ),
          ),

        // ── Add reading row ──────────────────────────────────────────────────
        if (status != StabStatus.stabilized && status != StabStatus.justifiedException)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 17, color: AppColors.teal, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: 'Leitura ${readings.length + 1}…',
                    hintStyle: const TextStyle(fontSize: 13, color: AppColors.sub2),
                    suffixText: rule.unit,
                    suffixStyle: const TextStyle(fontSize: 10, color: AppColors.sub2),
                    border:        const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.line)),
                    enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFC0D8D8))),
                    focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.teal, width: 2)),
                    isDense: true,
                    contentPadding: const EdgeInsets.only(bottom: 4),
                  ),
                  onSubmitted: (_) => _addReading(),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _adding ? null : _addReading,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.tealLt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0x401A8A8A)),
                  ),
                  child: _adding
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal))
                      : const Text('+ Leitura', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.teal)),
                ),
              ),
            ]),
          ),

        // ── Remove last reading ──────────────────────────────────────────────
        if (readings.isNotEmpty && status != StabStatus.justifiedException)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: GestureDetector(
              onTap: () => widget.onRemoveLast(),
              child: const Text('↺ Remover última leitura', style: TextStyle(fontSize: 11, color: AppColors.sub, decoration: TextDecoration.underline)),
            ),
          ),

        const SizedBox(height: 2),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// READING CHIP — compact visual per reading with delta indicator
// ─────────────────────────────────────────────────────────────────────────────

class _ReadingChip extends StatelessWidget {
  final int index;
  final ParameterReading reading;
  final bool isLast;
  final Color fgColor;

  const _ReadingChip({
    required this.index,
    required this.reading,
    required this.isLast,
    required this.fgColor,
  });

  @override
  Widget build(BuildContext context) {
    final withinLimit = reading.isWithinLimit;
    Color chipColor;
    String deltaIcon = '';

    if (withinLimit == null) {
      chipColor = AppColors.raised;
    } else if (withinLimit) {
      chipColor = const Color(0xFFE8F5E9);
      deltaIcon = ' ✓';
    } else {
      chipColor = const Color(0xFFFFEBEE);
      deltaIcon = ' ✗';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: withinLimit == null
              ? AppColors.line
              : withinLimit
                  ? const Color(0x4016A34A)
                  : const Color(0x40DC2626),
        ),
      ),
      child: Column(children: [
        Text(
          'R${index + 1}$deltaIcon',
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: withinLimit == null
                ? AppColors.sub2
                : withinLimit
                    ? AppColors.green
                    : AppColors.danger,
          ),
        ),
        Text(
          reading.value.toStringAsFixed(2),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMain, fontFamily: 'monospace'),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STABILIZATION EXCEPTION MODAL
// Shown when the user tries to save with one or more unstabilized required params.
// Requires a technical justification for each.
// ─────────────────────────────────────────────────────────────────────────────

class _StabExceptionModal extends StatefulWidget {
  final List<String> paramNames;
  final CollectProvider collectProvider;
  final VoidCallback onConfirm;

  const _StabExceptionModal({
    required this.paramNames,
    required this.collectProvider,
    required this.onConfirm,
  });

  @override
  State<_StabExceptionModal> createState() => _StabExceptionModalState();
}

class _StabExceptionModalState extends State<_StabExceptionModal> {
  // One selected reason per param
  late final Map<String, String?> _reasons;
  late final Map<String, TextEditingController> _noteCtrls;

  @override
  void initState() {
    super.initState();
    _reasons  = { for (final p in widget.paramNames) p: null };
    _noteCtrls = { for (final p in widget.paramNames) p: TextEditingController() };
  }

  @override
  void dispose() {
    for (final c in _noteCtrls.values) { c.dispose(); }
    super.dispose();
  }

  bool get _allSelected => _reasons.values.every((r) => r != null);

  void _confirm() {
    for (final paramName in widget.paramNames) {
      final reason = _reasons[paramName];
      if (reason == null) continue;
      widget.collectProvider.setException(
        paramName,
        StabilizationException(
          parameterName:      paramName,
          predefinedReason:   reason,
          complementaryNotes: _noteCtrls[paramName]!.text.trim().isEmpty
              ? null
              : _noteCtrls[paramName]!.text.trim(),
          createdAt:          DateTime.now(),
        ),
      );
    }
    widget.onConfirm();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      decoration: const BoxDecoration(
        color: AppColors.surf,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Header
          Row(children: [
            Container(width: 32, height: 32, decoration: BoxDecoration(color: const Color(0x14F07A2A), borderRadius: BorderRadius.circular(8)),
                alignment: Alignment.center, child: const Text('⚠', style: TextStyle(fontSize: 16))),
            const SizedBox(width: 10),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Parâmetro(s) sem estabilização', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.warn)),
              Text('Justifique tecnicamente para prosseguir', style: TextStyle(fontSize: 11, color: AppColors.sub)),
            ])),
          ]),
          const SizedBox(height: 16),

          // NC suggestion note
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.line)),
            child: const Text(
              '💡 Se o ponto está inacessível ou inviável para coleta, considere registrar uma Não Conformidade em vez de justificar.',
              style: TextStyle(fontSize: 11, color: AppColors.sub, height: 1.5),
            ),
          ),
          const SizedBox(height: 16),

          // One block per unstabilized param
          ...widget.paramNames.map((paramName) => _ParamExceptionBlock(
            paramName:  paramName,
            selected:   _reasons[paramName],
            noteCtrl:   _noteCtrls[paramName]!,
            onSelect:   (r) => setState(() => _reasons[paramName] = r),
          )),

          const SizedBox(height: 16),

          // Buttons
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
                alignment: Alignment.center,
                child: const Text('Cancelar', style: TextStyle(fontSize: 13, color: AppColors.sub, fontWeight: FontWeight.w600)),
              ),
            )),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: AnimatedOpacity(
              opacity: _allSelected ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 150),
              child: GestureDetector(
                onTap: _allSelected ? _confirm : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(color: AppColors.warn, borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: const Text('Salvar com justificativa', style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w800)),
                ),
              ),
            )),
          ]),
        ]),
      ),
    );
  }
}

class _ParamExceptionBlock extends StatelessWidget {
  final String paramName;
  final String? selected;
  final TextEditingController noteCtrl;
  final ValueChanged<String> onSelect;

  const _ParamExceptionBlock({
    required this.paramName,
    required this.selected,
    required this.noteCtrl,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(paramName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMain)),
        const SizedBox(height: 8),
        ...kStabilizationExceptionReasons.map((reason) => GestureDetector(
          onTap: () => onSelect(reason),
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: selected == reason ? const Color(0x0FF07A2A) : AppColors.surf,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: selected == reason ? AppColors.warn : AppColors.line),
            ),
            child: Row(children: [
              Container(
                width: 16, height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: selected == reason ? AppColors.warn : AppColors.line, width: 2),
                ),
                child: selected == reason
                    ? Center(child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.warn, shape: BoxShape.circle)))
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(reason, style: TextStyle(fontSize: 12, color: selected == reason ? AppColors.warn : AppColors.textMain, fontWeight: selected == reason ? FontWeight.w600 : FontWeight.w400))),
            ]),
          ),
        )),
        const SizedBox(height: 6),
        TextField(
          controller: noteCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'Observação complementar (opcional)…',
            hintStyle: const TextStyle(fontSize: 11, color: AppColors.sub2),
            filled: true, fillColor: AppColors.surf,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.teal)),
            contentPadding: const EdgeInsets.all(8),
            isDense: true,
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SIMPLE PARAM ROW (non-stabilization parameters)
// ─────────────────────────────────────────────────────────────────────────────

class _ParamRow extends StatefulWidget {
  final Parameter param;
  const _ParamRow({required this.param});

  @override
  State<_ParamRow> createState() => _ParamRowState();
}

class _ParamRowState extends State<_ParamRow> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.param.value);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.param;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.isPre ? const Color(0x07F07A2A) : AppColors.surf,
        border: Border(
          bottom: const BorderSide(color: AppColors.line2),
          left: p.isPre ? const BorderSide(color: AppColors.warn, width: 3) : BorderSide.none,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(p.label, style: const TextStyle(fontSize: 13, color: AppColors.textMain)),
          if (p.isPre) const Text('pré-coleta', style: TextStyle(fontSize: 9, color: AppColors.warn)),
        ]),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 21, color: AppColors.teal, fontFamily: 'monospace', fontWeight: FontWeight.w500),
            onChanged: (v) => widget.param.value = v,
            decoration: const InputDecoration(
              border:        UnderlineInputBorder(borderSide: BorderSide(color: AppColors.line)),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFC0D8D8))),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.teal, width: 2)),
              isDense: true,
              contentPadding: EdgeInsets.only(bottom: 4),
            ),
          )),
          Padding(
            padding: const EdgeInsets.only(left: 10, bottom: 4),
            child: Text(p.unit, style: const TextStyle(fontSize: 9, color: AppColors.sub2)),
          ),
          if (p.previousValue != null)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Text('ant. ${p.previousValue}', style: const TextStyle(fontSize: 10, color: AppColors.sub)),
            ),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CUSTODY FIELD
// ─────────────────────────────────────────────────────────────────────────────

class _CustodyField extends StatelessWidget {
  final String label;
  final String hint;
  const _CustodyField({required this.label, required this.hint});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.sub)),
    const SizedBox(height: 4),
    TextField(
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12, color: AppColors.sub2),
        filled: true, fillColor: AppColors.surf,
        border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.teal)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
    ),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// NC MODAL (unchanged from original)
// ─────────────────────────────────────────────────────────────────────────────

class _NcModal extends StatefulWidget {
  final void Function(String) onConfirm;
  const _NcModal({required this.onConfirm});

  @override
  State<_NcModal> createState() => _NcModalState();
}

class _NcModalState extends State<_NcModal> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      decoration: const BoxDecoration(
        color: AppColors.surf,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Não Conformidade', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.danger)),
        const Text('Selecione o motivo da não coleta', style: TextStyle(fontSize: 12, color: AppColors.sub)),
        const SizedBox(height: 14),
        ...kNcMotives.map((m) => GestureDetector(
          onTap: () => setState(() => _selected = m),
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _selected == m ? const Color(0x08DC2626) : AppColors.surf,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _selected == m ? AppColors.danger : AppColors.line),
            ),
            child: Row(children: [
              Container(
                width: 18, height: 18,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _selected == m ? AppColors.danger : AppColors.line, width: 2)),
                child: _selected == m
                    ? const Center(child: SizedBox(width: 8, height: 8, child: DecoratedBox(decoration: BoxDecoration(color: AppColors.danger, shape: BoxShape.circle))))
                    : null,
              ),
              const SizedBox(width: 12),
              Text(m, style: TextStyle(fontSize: 13, color: _selected == m ? AppColors.danger : AppColors.textMain, fontWeight: _selected == m ? FontWeight.w600 : FontWeight.w400)),
            ]),
          ),
        )),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
              alignment: Alignment.center,
              child: const Text('Cancelar', style: TextStyle(fontSize: 13, color: AppColors.sub, fontWeight: FontWeight.w600)),
            ),
          )),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: GestureDetector(
            onTap: _selected == null ? null : () => widget.onConfirm(_selected!),
            child: AnimatedOpacity(
              opacity: _selected == null ? 0.4 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: const Text('Confirmar NC', style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w800)),
              ),
            ),
          )),
        ]),
        const SizedBox(height: 20),
      ]),
    );
  }
}
