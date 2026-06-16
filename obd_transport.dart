import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'obd_transport.dart';

/// Транспорт для ELM327-адаптеров с Bluetooth Low Energy.
///
/// Большинство дешёвых BLE-клонов (Vgate iCar, Veepeak, vLinker) используют
/// сервис FFE0 с одной характеристикой FFE1, которая одновременно
/// принимает запись и шлёт notify. Иногда встречается раздельная пара
/// (write FFE1 + notify FFE2) или сервис 18F0/FFF0 — поэтому ниже идёт
/// перебор кандидатов, а не жёсткая привязка.
class BleTransport implements ObdTransport {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;

  StreamSubscription? _notifySub;
  StreamSubscription? _connSub;

  final _incoming = StreamController<List<int>>.broadcast();
  final _state = StreamController<LinkState>.broadcast();

  @override
  Stream<List<int>> get incoming => _incoming.stream;
  @override
  Stream<LinkState> get linkState => _state.stream;
  @override
  bool get isConnected => _device?.isConnected ?? false;

  // Известные UUID сервисов ELM327-BLE клонов (16-битные, развёрнутые в 128).
  static final _candidateServices = <Guid>[
    Guid("0000ffe0-0000-1000-8000-00805f9b34fb"),
    Guid("0000fff0-0000-1000-8000-00805f9b34fb"),
    Guid("000018f0-0000-1000-8000-00805f9b34fb"),
  ];

  /// Сканируем эфир, ищем устройство с «обдшным» именем.
  Future<BluetoothDevice?> _scan() async {
    _state.add(LinkState.scanning);
    BluetoothDevice? found;

    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.device.platformName.toUpperCase();
        if (name.contains("OBD") ||
            name.contains("VLINK") ||
            name.contains("VEEPEAK") ||
            name.contains("ELM")) {
          found = r.device;
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
    await FlutterBluePlus.isScanning.where((s) => s == false).first;
    await sub.cancel();
    return found;
  }

  @override
  Future<void> connect() async {
    _device = await _scan();
    if (_device == null) {
      _state.add(LinkState.error);
      throw Exception("BLE OBD-адаптер не найден. Включи зажигание и Bluetooth.");
    }

    _state.add(LinkState.connecting);

    // следим за разрывом для авто-reconnect / UI
    _connSub = _device!.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected) {
        _state.add(LinkState.disconnected);
      }
    });

    await _device!.connect(timeout: const Duration(seconds: 12));

    // некоторым клонам нужен запрос увеличенного MTU,
    // иначе длинные ответы (VIN, multiline DTC) режутся
    try {
      await _device!.requestMtu(180);
    } catch (_) {/* не критично */}

    await _discoverCharacteristics();
    _state.add(LinkState.connected);
  }

  Future<void> _discoverCharacteristics() async {
    final services = await _device!.discoverServices();

    for (final svc in services) {
      if (!_candidateServices.contains(svc.uuid)) continue;

      for (final c in svc.characteristics) {
        final props = c.properties;
        if (props.write || props.writeWithoutResponse) _writeChar = c;
        if (props.notify || props.indicate) _notifyChar = c;
      }
    }

    // фолбэк: если по белому списку не нашли — берём любую подходящую пару
    if (_writeChar == null || _notifyChar == null) {
      for (final svc in services) {
        for (final c in svc.characteristics) {
          if ((c.properties.write || c.properties.writeWithoutResponse) &&
              _writeChar == null) {
            _writeChar = c;
          }
          if ((c.properties.notify || c.properties.indicate) &&
              _notifyChar == null) {
            _notifyChar = c;
          }
        }
      }
    }

    if (_writeChar == null || _notifyChar == null) {
      throw Exception("Не найдены характеристики для обмена данными");
    }

    await _notifyChar!.setNotifyValue(true);
    _notifySub = _notifyChar!.onValueReceived.listen((bytes) {
      _incoming.add(bytes); // отдаём сырые байты наверх
    });
  }

  @override
  Future<void> write(String command) async {
    if (_writeChar == null) throw Exception("Нет канала записи");
    // ВАЖНО: каждая команда ОБЯЗАНА заканчиваться \r, иначе ELM327 её игнорит.
    final data = utf8.encode("$command\r");
    // writeWithoutResponse быстрее; OBD-команды короткие и влезают в MTU.
    await _writeChar!.write(
      data,
      withoutResponse: _writeChar!.properties.writeWithoutResponse,
    );
  }

  @override
  Future<void> disconnect() async {
    await _notifySub?.cancel();
    await _connSub?.cancel();
    await _device?.disconnect();
    _state.add(LinkState.disconnected);
  }
}
