import 'package:flutter_test/flutter_test.dart';
import 'package:obd_scanner/core/obd_parsers.dart';

void main() {
  group('RPM (PID 0C)', () {
    test('410C1AF8 -> 1726 об/мин', () {
      // A=0x1A(26), B=0xF8(248): (26*256+248)/4 = 1726
      expect(ObdParsers.rpm('410C1AF8'), 1726);
    });
    test('холостой ход 410C0FA0 -> 1000', () {
      // A=0x0F(15), B=0xA0(160): (15*256+160)/4 = 4000/4 = 1000
      expect(ObdParsers.rpm('410C0FA0'), 1000);
    });
    test('NO DATA -> null', () {
      expect(ObdParsers.rpm('NODATA'), isNull);
    });
    test('мусор в начале строки отсекается', () {
      // адаптер иногда добавляет хвост; ищем валидный фрейм
      expect(ObdParsers.rpm('00410C1AF8'), 1726);
    });
  });

  group('Скорость (PID 0D)', () {
    test('410D3C -> 60 км/ч', () {
      expect(ObdParsers.speed('410D3C'), 60); // 0x3C = 60
    });
    test('стоянка 410D00 -> 0', () {
      expect(ObdParsers.speed('410D00'), 0);
    });
  });

  group('Температура ОЖ (PID 05)', () {
    test('41055A -> 50 °C', () {
      expect(ObdParsers.coolant('41055A'), 50); // 0x5A=90, 90-40=50
    });
    test('холодный двигатель 410528 -> 0 °C', () {
      expect(ObdParsers.coolant('410528'), 0); // 0x28=40, 40-40=0
    });
  });

  group('DTC (Mode 03)', () {
    test('430133 -> [P0133]', () {
      expect(ObdParsers.dtc('430133'), ['P0133']);
    });
    test('несколько кодов', () {
      // 0133 -> P0133, 0420 -> P0420
      expect(ObdParsers.dtc('4301330420'), ['P0133', 'P0420']);
    });
    test('нет ошибок 4300 -> []', () {
      expect(ObdParsers.dtc('430000'), isEmpty);
    });
  });

  group('Расширенные PID', () {
    test('MAF 0110 01F4 -> 5.0 г/с', () {
      expect(ObdParsers.maf('411001F4'), 5.0); // (1*256+244)/100
    });
    test('MAP 010B 64 -> 100 кПа', () {
      expect(ObdParsers.mapPressure('410B64'), 100);
    });
    test('опережение зажигания 010E 90 -> +8°', () {
      expect(ObdParsers.timingAdvance('410E90'), 8.0); // 0x90/2-64
    });
    test('темп. впуска 010F 50 -> 40 °C', () {
      expect(ObdParsers.intakeTemp('410F50'), 40);
    });
    test('уровень топлива 012F 7F -> ~49.8 %', () {
      expect(ObdParsers.fuelLevel('412F7F')!.toStringAsFixed(1), '49.8');
    });
    test('давление топлива 010A 50 -> 240 кПа', () {
      expect(ObdParsers.fuelPressure('410A50'), 240);
    });
    test('расход топлива из MAF=5 г/с -> ~1.64 л/ч', () {
      expect(ObdParsers.fuelRateFromMaf(5.0)!.toStringAsFixed(2), '1.64');
    });
  });
}
