import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/database_helper.dart';
import '../sync/sync_queue.dart';
import '../sync/sync_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SYNC DIAGNOSTICS SCREEN  (v2)
// Shows the recent sync log, quarantined failed items, and a retry button.
// Accessible from the Profile screen → "Diagnóstico de Sincronização".
// ─────────────────────────────────────────────────────────────────────────────

class SyncDiagnosticsScreen extends StatefulWidget {
  const SyncDiagnosticsScreen({super.key});

  @override
  State<SyncDiagnosticsScreen> createState() => _SyncDiagnosticsScreenState();
}

class _SyncDiagnosticsScreenState extends State<SyncDiagnosticsScreen> {
  List<Map<String, dynamic>> _logs = [];
  List<Map<String, dynamic>> _failedItems = [];
  bool _loading = true;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final logs  = await DatabaseHelper.instance.getRecentSyncLogs();
    final failed = await DatabaseHelper.instance.getFailedQueueItems();
    if (mounted) {
      setState(() {
        _logs = logs;
        _failedItems = failed;
        _loading = false;
      });
    }
  }

  Future<void> _retryAll() async {
    setState(() => _retrying = true);
    await SyncQueue.instance.retryFailed(reset: true);
    await SyncService.instance.syncNow();
    await _load();
    setState(() => _retrying = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Itens re-enfileirados para sincronização')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnóstico de Sync'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SectionHeader(
                    icon: Icons.warning_amber_rounded,
                    title: 'Itens com falha (${_failedItems.length})',
                    color: _failedItems.isEmpty
                        ? Colors.green
                        : theme.colorScheme.error,
                  ),
                  if (_failedItems.isEmpty)
                    const _EmptyCard(message: 'Nenhum item em falha.')
                  else ...[
                    ..._failedItems.map((r) => _FailedItemCard(row: r)),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _retrying ? null : _retryAll,
                      icon: _retrying
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.replay),
                      label: const Text('Tentar novamente (todos)'),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _SectionHeader(
                    icon: Icons.history,
                    title: 'Histórico de sincronizações',
                    color: theme.colorScheme.primary,
                  ),
                  if (_logs.isEmpty)
                    const _EmptyCard(message: 'Nenhuma sincronização registrada.')
                  else
                    ..._logs.map((r) => _SyncLogCard(row: r)),
                ],
              ),
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String message;
  const _EmptyCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(message,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey)),
      ),
    );
  }
}

class _FailedItemCard extends StatelessWidget {
  final Map<String, dynamic> row;
  const _FailedItemCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final entity   = row['entity'] as String? ?? '—';
    final extId    = row['external_id'] as String? ?? '—';
    final attempts = row['attempts'] as int? ?? 0;
    final error    = row['last_error'] as String? ?? '—';
    final updatedAt = _fmtDate(row['updated_at'] as String?);

    // Calculate remaining backoff so the technician knows when auto-retry fires.
    final item = SyncQueueItem.fromRow(row);
    final secsLeft = item.secondsUntilRetry();
    final backoffLabel = secsLeft > 0
        ? 'Próxima tentativa em ${_fmtDuration(secsLeft)}'
        : 'Pronta para retry';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _EntityChip(entity: entity),
                const Spacer(),
                Text('$attempts tentativas',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 4),
            Text(extId,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(error,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.access_time, size: 12, color: Colors.grey),
              const SizedBox(width: 4),
              Text(updatedAt,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const Spacer(),
              Text(backoffLabel,
                  style: TextStyle(
                      fontSize: 11,
                      color: secsLeft > 0 ? Colors.orange : Colors.green)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _SyncLogCard extends StatelessWidget {
  final Map<String, dynamic> row;
  const _SyncLogCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final status      = row['status'] as String? ?? '—';
    final startedAt   = _fmtDate(row['started_at'] as String?);
    final total       = row['items_total']     as int? ?? 0;
    final processed   = row['items_processed'] as int? ?? 0;
    final failed      = row['items_failed']    as int? ?? 0;
    final conflict    = row['items_conflict']  as int? ?? 0;
    final duplicated  = row['items_duplicated']as int? ?? 0;
    final errorMsg    = row['error_message']   as String?;

    final isOk = status == 'completed' && failed == 0;
    final color = isOk ? Colors.green : (status == 'failed' ? Colors.red : Colors.orange);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isOk ? Icons.check_circle_outline : Icons.error_outline,
                  size: 16, color: color,
                ),
                const SizedBox(width: 6),
                Text(startedAt,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                const Spacer(),
                _StatusChip(status: status, color: color),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              children: [
                _StatLabel('Total',      total.toString()),
                _StatLabel('Enviados',   processed.toString()),
                _StatLabel('Falhas',     failed.toString(),   color: failed > 0 ? Colors.red : null),
                _StatLabel('Conflitos',  conflict.toString(), color: conflict > 0 ? Colors.orange : null),
                _StatLabel('Duplicados', duplicated.toString()),
              ],
            ),
            if (errorMsg != null) ...[
              const SizedBox(height: 4),
              Text(errorMsg,
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.error),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
    );
  }
}

class _EntityChip extends StatelessWidget {
  final String entity;
  const _EntityChip({required this.entity});

  @override
  Widget build(BuildContext context) {
    final label = switch (entity) {
      'mobile_campaign'     => 'Campanha',
      'collection_point'    => 'Ponto',
      'collection_record'   => 'Registro',
      'collection_evidence' => 'Foto',
      _ => entity,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSecondaryContainer)),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final Color color;
  const _StatusChip({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(status,
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _StatLabel extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _StatLabel(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style.copyWith(fontSize: 12),
        children: [
          TextSpan(text: '$label: ',
              style: const TextStyle(color: Colors.grey)),
          TextSpan(text: value,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: color ?? DefaultTextStyle.of(context).style.color)),
        ],
      ),
    );
  }
}

String _fmtDate(String? iso) {
  if (iso == null) return '—';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return DateFormat('dd/MM/yy HH:mm').format(dt);
  } catch (_) {
    return iso;
  }
}

String _fmtDuration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final m = seconds ~/ 60;
  if (m < 60) return '${m}min';
  return '${m ~/ 60}h${m % 60}min';
}
