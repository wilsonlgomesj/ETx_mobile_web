import 'package:flutter/material.dart';
import 'models.dart';
import 'database/database_helper.dart';
import 'api/auth_service.dart';
import 'sync/sync_service.dart';

class AppState extends ChangeNotifier {
  String? activeCampaignId;
  bool fieldWork = false;
  int syncPending = 0;
  bool isOffline = false;
  String units = 'SI';

  // Campaigns loaded from DB
  List<Campaign> campaigns = [];

  // Current field session
  List<FieldPoint> points = [];
  int currentPointIndex = 0;
  bool campaignFinished = false;

  // Profile
  String userName = 'Carlos Almeida';
  String userRole = 'Hidrólogo Sênior';
  String userReg = 'CRBio 4821-06/D';
  String userEmail = 'carlos@envirotrack.com';
  String userPhone = '+55 11 98765-4321';
  String userCompany = 'EnviroTrack Consultoria';
  String userInitials = 'CA';

  // Notifications
  int notifCount = 0;

  Future<void> init() async {
    // 1) Restaura sessão (se existir) e hidrata perfil a partir dela.
    final session = await AuthService.instance.restore();
    if (session != null) {
      userName   = session.userName;
      userEmail  = session.userEmail;
      userInitials = _initials(userName);
    }

    // 2) Carrega campanhas locais do SQLite (source of truth operacional).
    campaigns = await DatabaseHelper.instance.getCampaigns();

    // 3) Liga o sync service e faz bind reativo nos indicadores de UI.
    await SyncService.instance.start();
    SyncService.instance.state.addListener(_onSyncStateChanged);
    SyncService.instance.isOnline.addListener(_onConnectivityChanged);

    // 4) Sincroniza as contagens iniciais.
    _onSyncStateChanged();
    _onConnectivityChanged();

    // 5) Primeiro pull/push oportunista (não bloqueia o boot).
    if (AuthService.instance.isAuthenticated) {
      // ignore: discarded_futures
      SyncService.instance.syncNow();
    }

    notifyListeners();
  }

  void _onSyncStateChanged() {
    final s = SyncService.instance.state.value;
    syncPending = s.pendingCount;
    notifyListeners();
  }

  void _onConnectivityChanged() {
    isOffline = !SyncService.instance.isOnline.value;
    notifyListeners();
  }

  bool get isAuthenticated => AuthService.instance.isAuthenticated;

  Future<void> logout() async {
    await AuthService.instance.logout();
    notifyListeners();
  }

  Future<void> refreshCampaignsFromLocal() async {
    campaigns = await DatabaseHelper.instance.getCampaigns();
    notifyListeners();
  }

  Campaign? get activeCampaign {
    if (activeCampaignId == null) return null;
    try {
      return campaigns.firstWhere((c) => c.id == activeCampaignId);
    } catch (_) {
      return null;
    }
  }

  int get doneCount => points.where((p) => p.status == PointStatus.done).length;
  int get ncCount   => points.where((p) => p.status == PointStatus.nc).length;
  int get pendCount => points.where((p) => p.status == PointStatus.pending).length;
  double get progress => points.isEmpty ? 0.0 : (doneCount + ncCount) / points.length;

  Future<void> startCampaign(String campId) async {
    activeCampaignId = campId;
    fieldWork = true;
    campaignFinished = false;
    currentPointIndex = 0;
    points = await DatabaseHelper.instance.getPointsByCampaign(campId);
    notifyListeners();
  }

  void openPoint(int idx) {
    currentPointIndex = idx;
    notifyListeners();
  }

  Future<void> markPointDone(int idx) async {
    if (idx < points.length) {
      points[idx].status = PointStatus.done;
      if (activeCampaignId != null) {
        await DatabaseHelper.instance.markPointDone(
          activeCampaignId!, points[idx].code,
          gpsLat: points[idx].gpsLat,
          gpsLng: points[idx].gpsLng,
        );
        await _syncCampaignProgress();

        // Enfileira o ponto + record (stabilização já persistida pelo provider)
        // para upload ao backend quando houver conexão.
        await SyncService.instance.enqueuePointWithRecord(
          activeCampaignId!, points[idx].code,
        );
        await SyncService.instance.enqueueCampaign(activeCampaignId!);
        // ignore: discarded_futures
        SyncService.instance.syncNow();
      }
      notifyListeners();
    }
  }

  Future<void> markPointNc(int idx, String motive) async {
    if (idx < points.length) {
      points[idx].status = PointStatus.nc;
      points[idx].ncMotive = motive;
      points[idx].ncReported = true;
      if (activeCampaignId != null) {
        await DatabaseHelper.instance.markPointNc(
            activeCampaignId!, points[idx].code, motive);
        await _syncCampaignProgress();

        await SyncService.instance.enqueuePointWithRecord(
          activeCampaignId!, points[idx].code,
        );
        await SyncService.instance.enqueueCampaign(activeCampaignId!);
        // ignore: discarded_futures
        SyncService.instance.syncNow();
      }
      notifyListeners();
    }
  }

  Future<void> setPointGps(int idx, String lat, String lng) async {
    if (idx < points.length) {
      points[idx].gpsLat = lat;
      points[idx].gpsLng = lng;
      if (activeCampaignId != null) {
        await DatabaseHelper.instance
            .setPointGps(activeCampaignId!, points[idx].code, lat, lng);
        await SyncService.instance.enqueuePoint(
          activeCampaignId!, points[idx].code,
        );
      }
      notifyListeners();
    }
  }

  void setPointParam(int idx, String paramLabel, String value) {
    if (idx < points.length) {
      points[idx].params[paramLabel] = value;
      notifyListeners();
    }
  }

  void toggleOffline() {
    // Kept for manual dev/testing override. In production the real state comes
    // from SyncService.instance.isOnline via _onConnectivityChanged().
    isOffline = !isOffline;
    notifyListeners();
  }

  /// Manual "Sync now" button — push then pull. Does nothing when offline
  /// or when the user isn't authenticated.
  Future<void> doSync() async {
    await SyncService.instance.syncNow();
    syncPending = SyncService.instance.state.value.pendingCount;
    notifyListeners();
  }

  Future<void> finishCampaign() async {
    campaignFinished = true;
    fieldWork = false;
    if (activeCampaignId != null) {
      await DatabaseHelper.instance
          .updateCampaignStatus(activeCampaignId!, 'concluida');
      campaigns = await DatabaseHelper.instance.getCampaigns();

      // Enfileira a campanha com status final; cada ponto já foi enfileirado
      // quando done/NC. O push tenta agora e o sync service também re-tentará
      // periodicamente em background.
      await SyncService.instance.enqueueCampaign(activeCampaignId!);
      // ignore: discarded_futures
      SyncService.instance.syncNow();
    }
    syncPending = SyncService.instance.state.value.pendingCount;
    notifyListeners();
  }

  Future<void> _syncCampaignProgress() async {
    if (activeCampaignId == null) return;
    final done = doneCount + ncCount;
    await DatabaseHelper.instance
        .updateCampaignProgress(activeCampaignId!, done);
    campaigns = await DatabaseHelper.instance.getCampaigns();
  }

  void updateProfile({
    String? name,
    String? role,
    String? reg,
    String? email,
    String? phone,
    String? company,
  }) {
    if (name != null) { userName = name; userInitials = _initials(name); }
    if (role != null) userRole = role;
    if (reg != null) userReg = reg;
    if (email != null) userEmail = email;
    if (phone != null) userPhone = phone;
    if (company != null) userCompany = company;
    notifyListeners();
  }

  void toggleUnits() {
    units = units == 'SI' ? 'USC' : 'SI';
    notifyListeners();
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    if (parts.isNotEmpty && parts.first.isNotEmpty) return parts.first[0].toUpperCase();
    return 'U';
  }

  int get nextPendingIndex {
    for (int i = 0; i < points.length; i++) {
      if (points[i].status == PointStatus.pending) return i;
    }
    return -1;
  }

  @override
  void dispose() {
    SyncService.instance.state.removeListener(_onSyncStateChanged);
    SyncService.instance.isOnline.removeListener(_onConnectivityChanged);
    SyncService.instance.stop();
    super.dispose();
  }
}
