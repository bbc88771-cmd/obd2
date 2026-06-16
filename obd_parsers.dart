import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../transport/obd_transport.dart';
import '../state/connection_provider.dart';
import 'gauge_widget.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    final kind = ref.watch(transportKindProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0E1116),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text("OBD Scanner"),
        actions: [_StatusChip(conn.link)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _TransportSelector(kind: kind),
            const SizedBox(height: 12),
            _ConnectBar(state: conn),
            if (conn.error != null) ...[
              const SizedBox(height: 8),
              Text(conn.error!,
                  style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 16),
            const Expanded(child: _GaugesGrid()),
            const _DtcPanel(),
          ],
        ),
      ),
    );
  }
}

class _TransportSelector extends ConsumerWidget {
  final TransportKind kind;
  const _TransportSelector({required this.kind});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SegmentedButton<TransportKind>(
      segments: const [
        ButtonSegment(value: TransportKind.ble, label: Text("BLE")),
        ButtonSegment(value: TransportKind.btClassic, label: Text("BT")),
        ButtonSegment(value: TransportKind.wifi, label: Text("Wi-Fi")),
      ],
      selected: {kind},
      onSelectionChanged: (s) =>
          ref.read(transportKindProvider.notifier).state = s.first,
    );
  }
}

class _ConnectBar extends ConsumerWidget {
  final ConnectionUiState state;
  const _ConnectBar({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConnected = state.link == LinkState.connected;
    final busy = state.link == LinkState.connecting ||
        state.link == LinkState.initializing ||
        state.link == LinkState.scanning;

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        icon: Icon(isConnected ? Icons.link_off : Icons.bluetooth_searching),
        label: Text(busy
            ? "Подключение…"
            : isConnected
                ? "Отключить"
                : "Подключить адаптер"),
        onPressed: busy
            ? null
            : () {
                final ctrl = ref.read(connectionProvider.notifier);
                if (isConnected) {
                  ctrl.disconnect();
                } else {
                  ctrl.connect(ref.read(transportKindProvider));
                }
              },
      ),
    );
  }
}

class _GaugesGrid extends ConsumerWidget {
  const _GaugesGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tele = ref.watch(telemetryProvider);

    return tele.when(
      data: (t) => GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        children: [
          GaugeWidget(
              label: "Обороты",
              unit: "об/мин",
              value: (t.rpm ?? 0).toDouble(),
              maxValue: 8000,
              color: Colors.cyanAccent),
          GaugeWidget(
              label: "Скорость",
              unit: "км/ч",
              value: (t.speed ?? 0).toDouble(),
              maxValue: 240,
              color: Colors.greenAccent),
          GaugeWidget(
              label: "Темп. ОЖ",
              unit: "°C",
              value: (t.coolant ?? 0).toDouble(),
              maxValue: 130,
              color: Colors.orangeAccent),
          GaugeWidget(
              label: "Нагрузка",
              unit: "%",
              value: t.load ?? 0,
              maxValue: 100,
              color: Colors.purpleAccent),
          GaugeWidget(
              label: "Наддув (MAP)",
              unit: "кПа",
              value: (t.map ?? 0).toDouble(),
              maxValue: 250,
              color: Colors.tealAccent),
          GaugeWidget(
              label: "Топливо",
              unit: "%",
              value: t.fuelLevel ?? 0,
              maxValue: 100,
              color: Colors.amberAccent),
          GaugeWidget(
              label: "Расход",
              unit: "л/ч",
              value: t.fuelRate ?? 0,
              maxValue: 30,
              color: Colors.lightBlueAccent),
          GaugeWidget(
              label: "Темп. впуска",
              unit: "°C",
              value: (t.intakeTemp ?? 0).toDouble(),
              maxValue: 90,
              color: Colors.pinkAccent),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text("Нет данных: $e",
            style: const TextStyle(color: Colors.redAccent)),
      ),
    );
  }
}

class _DtcPanel extends ConsumerStatefulWidget {
  const _DtcPanel();
  @override
  ConsumerState<_DtcPanel> createState() => _DtcPanelState();
}

class _DtcPanelState extends ConsumerState<_DtcPanel> {
  List<String> _codes = [];
  bool _loading = false;

  Future<void> _read() async {
    final svc = ref.read(connectionProvider.notifier).service;
    if (svc == null) return;
    setState(() => _loading = true);
    try {
      final codes = await svc.readDtc();
      setState(() => _codes = codes);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _clear() async {
    final svc = ref.read(connectionProvider.notifier).service;
    if (svc == null) return;

    // ОБЯЗАТЕЛЬНОЕ подтверждение перед записью в шину
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Сбросить ошибки?"),
        content: const Text(
            "Check Engine погаснет, freeze frame будет стёрт. "
            "Автомобиль должен стоять (V=0). Продолжить?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Отмена")),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Сбросить")),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await svc.clearDtc(userConfirmed: true);
      setState(() => _codes = []);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Ошибки сброшены")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("$e"), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected =
        ref.watch(connectionProvider).link == LinkState.connected;

    return Card(
      color: const Color(0xFF161B22),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text("Ошибки (DTC)",
                    style: TextStyle(color: Colors.white, fontSize: 16)),
                const Spacer(),
                TextButton(
                    onPressed: connected && !_loading ? _read : null,
                    child: const Text("Прочитать")),
                TextButton(
                    onPressed: connected && _codes.isNotEmpty ? _clear : null,
                    child: const Text("Сбросить",
                        style: TextStyle(color: Colors.redAccent))),
              ],
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_codes.isEmpty && !_loading)
              const Text("Кодов нет",
                  style: TextStyle(color: Colors.white38))
            else
              Wrap(
                spacing: 8,
                children: _codes
                    .map((c) => Chip(
                          label: Text(c),
                          backgroundColor: Colors.red.shade900,
                          labelStyle: const TextStyle(color: Colors.white),
                        ))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final LinkState link;
  const _StatusChip(this.link);

  @override
  Widget build(BuildContext context) {
    final map = {
      LinkState.disconnected: ("Отключено", Colors.grey),
      LinkState.scanning: ("Поиск…", Colors.amber),
      LinkState.connecting: ("Подключение…", Colors.amber),
      LinkState.initializing: ("Инициализация…", Colors.amber),
      LinkState.connected: ("Онлайн", Colors.green),
      LinkState.error: ("Ошибка", Colors.red),
    };
    final (text, color) = map[link]!;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Chip(
        label: Text(text, style: const TextStyle(fontSize: 12)),
        backgroundColor: color.withOpacity(0.2),
        side: BorderSide(color: color),
      ),
    );
  }
}
