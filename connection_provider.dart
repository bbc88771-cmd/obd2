import 'dart:async';
import '../transport/obd_transport.dart';
import 'obd_connection.dart';
import 'request_queue.dart';
import 'obd_parsers.dart';

/// Снимок телеметрии для UI.
class Telemetry {
  final int? rpm;
  final int? speed;
  final int? coolant;
  final double? load;
  final double? voltage;
  // расширенные
  final int? intakeTemp;
  final double? fuelLevel;
  final double? maf;
  final int? map;
  final double? timing;
  final int? ambient;
  final double? fuelRate; // л/ч, расчётный из MAF

  const Telemetry({
    this.rpm,
    this.speed,
    this.coolant,
    this.load,
    this.voltage,
    this.intakeTemp,
    this.fuelLevel,
    this.maf,
    this.map,
    this.timing,
    this.ambient,
    this.fuelRate,
  });

  Telemetry copyWith({
    int? rpm,
    int? speed,
    int? coolant,
    double? load,
    double? voltage,
    int? intakeTemp,
    double? fuelLevel,
    double? maf,
    int? map,
    double? timing,
    int? ambient,
    double? fuelRate,
  }) =>
      Telemetry(
        rpm: rpm ?? this.rpm,
        speed: speed ?? this.speed,
        coolant: coolant ?? this.coolant,
        load: load ?? this.load,
        voltage: voltage ?? this.voltage,
        intakeTemp: intakeTemp ?? this.intakeTemp,
        fuelLevel: fuelLevel ?? this.fuelLevel,
        maf: maf ?? this.maf,
        map: map ?? this.map,
        timing: timing ?? this.timing,
        ambient: ambient ?? this.ambient,
        fuelRate: fuelRate ?? this.fuelRate,
      );
}

/// Главный доменный слой: инициализация адаптера, цикл опроса,
/// чтение/сброс ошибок и контроль безопасности.
class ObdService {
  final ObdTransport transport;
  late final ObdConnection _conn;
  late final RequestQueue _queue;

  final _telemetry = StreamController<Telemetry>.broadcast();
  Stream<Telemetry> get telemetry => _telemetry.stream;
  Telemetry _last = const Telemetry();

  Timer? _pollTimer;
  int _consecutiveTimeouts = 0;

  ObdService(this.transport) {
    _conn = ObdConnection(transport);
    _queue = RequestQueue(_conn);
  }

  /// Полная инициализация ELM327. Порядок команд важен.
  Future<void> initialize() async {
    // ATZ — полный сброс, адаптер «думает» ~1 сек, даём больше времени.
    await _queue.enqueue("ATZ", timeout: const Duration(seconds: 3));
    await _queue.enqueue("ATE0"); // Echo Off — ответ без копии нашей команды
    await _queue.enqueue("ATL0"); // Linefeed Off — без лишних \n
    await _queue.enqueue("ATS0"); // Spaces Off — компактный HEX "410C1AF8"
    await _queue.enqueue("ATH0"); // Headers Off — на этапе значений не нужны
    await _queue.enqueue("ATSP0"); // авто-определение протокола авто
    // «пробный» OBD-запрос — заставляет адаптер реально выбрать протокол
    await _queue.enqueue("0100", timeout: const Duration(seconds: 5));
    // выясняем, какие PID реально поддерживает ЭБУ этого авто
    await detectSupportedPids();
  }

  /// Запустить периодический опрос (poll loop) с заданной частотой.
  void startPolling({Duration interval = const Duration(milliseconds: 200)}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(interval, (_) => _pollOnce());
  }

  void stopPolling() => _pollTimer?.cancel();

  Future<void> _pollOnce() async {
    // Все команды идут через очередь, поэтому не накладываются.
    await _read(Pid.rpm.cmd, (r) {
      final v = ObdParsers.rpm(r);
      if (v != null) _emit(_last.copyWith(rpm: v));
    });
    await _read(Pid.speed.cmd, (r) {
      final v = ObdParsers.speed(r);
      if (v != null) _emit(_last.copyWith(speed: v));
    });
    await _read(Pid.coolant.cmd, (r) {
      final v = ObdParsers.coolant(r);
      if (v != null) _emit(_last.copyWith(coolant: v));
    });
    await _read(Pid.load.cmd, (r) {
      final v = ObdParsers.engineLoad(r);
      if (v != null) _emit(_last.copyWith(load: v));
    });
    await _read("ATRV", (r) {
      final v = ObdParsers.voltage(r);
      if (v != null) _emit(_last.copyWith(voltage: v));
    });

    // расширенные PID опрашиваем только если ЭБУ их поддерживает
    // (проверка через 0100/0120 — список поддержки, см. _detectSupported)
    if (_supports("0F")) {
      await _read(Pid.intakeTemp.cmd, (r) {
        final v = ObdParsers.intakeTemp(r);
        if (v != null) _emit(_last.copyWith(intakeTemp: v));
      });
    }
    if (_supports("2F")) {
      await _read(Pid.fuelLevel.cmd, (r) {
        final v = ObdParsers.fuelLevel(r);
        if (v != null) _emit(_last.copyWith(fuelLevel: v));
      });
    }
    if (_supports("10")) {
      await _read(Pid.maf.cmd, (r) {
        final v = ObdParsers.maf(r);
        if (v != null) {
          // попутно считаем мгновенный расход топлива
          final rate = ObdParsers.fuelRateFromMaf(v);
          _emit(_last.copyWith(maf: v, fuelRate: rate));
        }
      });
    }
    if (_supports("0B")) {
      await _read(Pid.map.cmd, (r) {
        final v = ObdParsers.mapPressure(r);
        if (v != null) _emit(_last.copyWith(map: v));
      });
    }
    if (_supports("0E")) {
      await _read(Pid.timing.cmd, (r) {
        final v = ObdParsers.timingAdvance(r);
        if (v != null) _emit(_last.copyWith(timing: v));
      });
    }
    if (_supports("46")) {
      await _read(Pid.ambient.cmd, (r) {
        final v = ObdParsers.ambientTemp(r);
        if (v != null) _emit(_last.copyWith(ambient: v));
      });
    }
  }

  // ─────────── автоопределение поддерживаемых PID ───────────
  // ЭБУ на запрос 0100 возвращает битовую маску: какие PID 01-20 поддержаны.
  final Set<String> _supported = {};

  bool _supports(String pid) => _supported.contains(pid.toUpperCase());

  /// Запрашивает маски поддержки (0100, 0120, 0140) и заполняет _supported.
  /// Вызывается один раз после initialize().
  Future<void> detectSupportedPids() async {
    for (final base in ["0100", "0120", "0140"]) {
      try {
        final resp = await _queue.enqueue(base);
        _parseSupportMask(resp, base);
      } catch (_) {/* блок не поддержан — ок */}
    }
  }

  void _parseSupportMask(String resp, String base) {
    // ответ вида 41 00 BE 1F A8 13 → 4 байта маски = 32 бита = PID 01..20
    final pidByte = base.substring(2); // "00","20","40"
    final d = ObdParsers.extractData(resp, "01", pidByte);
    if (d == null || d.length < 4) return;

    final offset = int.parse(pidByte, radix: 16); // 0x00, 0x20, 0x40
    int bit = 0;
    for (final byte in d.take(4)) {
      for (int i = 7; i >= 0; i--) {
        bit++;
        if ((byte & (1 << i)) != 0) {
          final pidNum = offset + bit;
          _supported.add(pidNum.toRadixString(16).padLeft(2, '0').toUpperCase());
        }
      }
    }
  }

  Future<void> _read(String cmd, void Function(String) onOk) async {
    try {
      final resp = await _queue.enqueue(cmd);
      _consecutiveTimeouts = 0; // успех — сбрасываем счётчик
      onOk(resp);
    } on TimeoutException {
      _consecutiveTimeouts++;
      // 3 таймаута подряд → линк, скорее всего, умер
      if (_consecutiveTimeouts >= 3) {
        stopPolling();
        _telemetry.addError(StateError("Соединение потеряно"));
      }
    } catch (_) {/* битый ответ — просто пропускаем кадр */}
  }

  void _emit(Telemetry t) {
    _last = t;
    _telemetry.add(t);
  }

  /// Прочитать сохранённые коды ошибок.
  Future<List<String>> readDtc() async {
    final resp = await _queue.enqueue("03", timeout: const Duration(seconds: 3));
    return ObdParsers.dtc(resp);
  }

  /// БЕЗОПАСНОСТЬ: проверка, что машина неподвижна перед записью.
  Future<bool> _isSafeToWrite() async {
    try {
      final resp = await _queue.enqueue(Pid.speed.cmd);
      final speed = ObdParsers.speed(resp);
      // нет данных → считаем НЕбезопасным (fail-safe)
      return speed == 0;
    } catch (_) {
      return false;
    }
  }

  /// Сброс DTC (Mode 04). Только на стоящей машине + подтверждение в UI.
  /// Гасит Check Engine и стирает freeze frame — необратимо.
  Future<void> clearDtc({required bool userConfirmed}) async {
    if (!userConfirmed) {
      throw Exception("Требуется подтверждение пользователя");
    }
    if (!await _isSafeToWrite()) {
      throw Exception("Сброс ошибок запрещён: автомобиль должен стоять (V=0)");
    }
    await _queue.enqueue("04", timeout: const Duration(seconds: 3));
  }

  Future<void> dispose() async {
    stopPolling();
    _queue.clear();
    await _conn.dispose();
    await _telemetry.close();
  }
}
