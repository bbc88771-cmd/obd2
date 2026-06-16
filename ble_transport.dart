import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'obd_transport.dart';

/// Транспорт для Wi-Fi ELM327-адаптеров.
///
/// Такие адаптеры поднимают собственную точку доступа и работают как
/// TCP-сервер. Классический дефолт у клонов: 192.168.0.10 порт 35000.
/// Телефон должен быть подключён к Wi-Fi-сети самого адаптера.
class WifiTransport implements ObdTransport {
  final String host;
  final int port;

  Socket? _socket;
  StreamSubscription? _sub;

  final _incoming = StreamController<List<int>>.broadcast();
  final _state = StreamController<LinkState>.broadcast();

  WifiTransport({this.host = "192.168.0.10", this.port = 35000});

  @override
  Stream<List<int>> get incoming => _incoming.stream;
  @override
  Stream<LinkState> get linkState => _state.stream;
  @override
  bool get isConnected => _socket != null;

  @override
  Future<void> connect() async {
    _state.add(LinkState.connecting);
    try {
      _socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 8),
      );

      // поток байтов из сокета — тот же контракт, что и у BLE
      _sub = _socket!.listen(
        (bytes) => _incoming.add(bytes),
        onError: (_) => _state.add(LinkState.error),
        onDone: () {
          _socket = null;
          _state.add(LinkState.disconnected);
        },
      );

      _state.add(LinkState.connected);
    } catch (e) {
      _state.add(LinkState.error);
      throw Exception("Не удалось подключиться к $host:$port. "
          "Проверь, что телефон в Wi-Fi-сети адаптера.");
    }
  }

  @override
  Future<void> write(String command) async {
    if (_socket == null) throw Exception("Сокет закрыт");
    _socket!.add(utf8.encode("$command\r")); // \r обязателен
    await _socket!.flush();
  }

  @override
  Future<void> disconnect() async {
    await _sub?.cancel();
    await _socket?.close();
    _socket = null;
    _state.add(LinkState.disconnected);
  }
}
