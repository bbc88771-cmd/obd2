import 'dart:async';

/// Состояние соединения. Используется конечным автоматом в Riverpod.
enum LinkState { disconnected, scanning, connecting, initializing, connected, error }

/// Единый контракт для всех физических каналов связи с ELM327.
///
/// Благодаря этой абстракции доменный слой (ObdService) НЕ знает,
/// через что он говорит с адаптером — BLE, Bluetooth Classic или Wi-Fi.
/// Чтобы добавить новый транспорт — достаточно реализовать этот интерфейс.
abstract class ObdTransport {
  /// Установить физическое соединение (скан + подключение).
  Future<void> connect();

  /// Разорвать соединение и освободить ресурсы.
  Future<void> disconnect();

  /// Отправить ASCII-команду адаптеру.
  /// Завершающий символ \r (0x0D) добавляет сама реализация.
  Future<void> write(String command);

  /// Сырой поток байтов ОТ адаптера. Приходит кусками (chunks),
  /// сборкой целого ответа занимается слой выше (ObdConnection).
  Stream<List<int>> get incoming;

  bool get isConnected;

  /// Поток изменений состояния линка (для авто-reconnect и UI).
  Stream<LinkState> get linkState;
}
