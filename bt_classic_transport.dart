import 'dart:async';
import 'dart:convert';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';
import 'obd_transport.dart';

/// Транспорт для классических SPP Bluetooth ELM327 (самый частый тип адаптера).
/// Работает ТОЛЬКО на Android — у iOS нет публичного SPP-доступа,
/// там используем BLE или Wi-Fi.
class BtClassicTransport implements ObdTransport {
  final String? deviceAddress; // MAC; если null — берём первый спаренный OBD

  BluetoothConnection? _connection;
  StreamSubscription? _sub;

  final _incoming = StreamController<List<int>>.broadcast();
  final _state = StreamController<LinkState>.broadcast();

  BtClassicTransport({this.deviceAddress});

  @override
  Stream<List<int>> get incoming => _incoming.stream;
  @override
  Stream<LinkState> get linkState => _state.stream;
  @override
  bool get isConnected => _connection?.isConnected ?? false;

  Future<String?> _resolveAddress() async {
    if (deviceAddress != null) return deviceAddress;
    // среди спаренных устройств ищем по имени
    final bonded = await FlutterBluetoothSerial.instance.getBondedDevices();
    for (final d in bonded) {
      final n = (d.name ?? "").toUpperCase();
      if (n.contains("OBD") || n.contains("ELM")) return d.address;
    }
    return null;
  }

  @override
  Future<void> connect() async {
    _state.add(LinkState.connecting);
    final addr = await _resolveAddress();
    if (addr == null) {
      _state.add(LinkState.error);
      throw Exception("Спаренный OBD-адаптер не найден. "
          "Сначала спарь его в настройках Bluetooth.");
    }

    _connection = await BluetoothConnection.toAddress(addr);

    _sub = _connection!.input?.listen(
      (bytes) => _incoming.add(bytes),
      onDone: () => _state.add(LinkState.disconnected),
    );

    _state.add(LinkState.connected);
  }

  @override
  Future<void> write(String command) async {
    if (_connection == null) throw Exception("Нет соединения");
    _connection!.output.add(Uint8List.fromList(utf8.encode("$command\r")));
    await _connection!.output.allSent;
  }

  @override
  Future<void> disconnect() async {
    await _sub?.cancel();
    await _connection?.close();
    _connection = null;
    _state.add(LinkState.disconnected);
  }
}
