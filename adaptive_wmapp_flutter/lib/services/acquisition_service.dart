import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as ble;
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart'
    as classic;
import 'package:permission_handler/permission_handler.dart';

import '../models/eeg_sample.dart';

enum DeviceKind { orbit, epidome, synthetic }

enum AcquisitionState { disconnected, scanning, connecting, streaming }

class EegDevice {
  const EegDevice({
    required this.name,
    required this.id,
    required this.kind,
    required this.isBle,
  });

  final String name;
  final String id;
  final DeviceKind kind;
  final bool isBle;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is EegDevice && other.id == id && other.isBle == isBle;
  }

  @override
  int get hashCode => Object.hash(id, isBle);
}

class AcquisitionService {
  final _state = StreamController<AcquisitionState>.broadcast();
  final _samples = StreamController<EegSample>.broadcast();
  final _devices = StreamController<List<EegDevice>>.broadcast();

  AcquisitionState _currentState = AcquisitionState.disconnected;
  final List<EegDevice> _seenDevices = [];
  final List<int> _classicBuffer = [];
  final List<int> _bleBuffer = [];
  String _orbitTextBuffer = '';
  final _random = Random();

  StreamSubscription<classic.BluetoothDiscoveryResult>? _classicScanSub;
  StreamSubscription<List<ble.ScanResult>>? _bleScanSub;
  StreamSubscription<Uint8List>? _classicInputSub;
  StreamSubscription<List<int>>? _bleNotifySub;
  classic.BluetoothConnection? _classicConnection;
  ble.BluetoothDevice? _bleDevice;
  Timer? _syntheticTimer;
  double _syntheticT = 0.0;

  Stream<AcquisitionState> get state => _state.stream;
  Stream<EegSample> get samples => _samples.stream;
  Stream<List<EegDevice>> get devices => _devices.stream;
  AcquisitionState get currentState => _currentState;

  Future<void> requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  Future<void> scan() async {
    await requestPermissions();
    _setState(AcquisitionState.scanning);
    _seenDevices.removeWhere((device) => device.kind != DeviceKind.synthetic);
    _publishDevices();

    // Query system connected devices
    try {
      final systemDevices = await ble.FlutterBluePlus.systemDevices([]);
      for (final device in systemDevices) {
        final name = device.platformName.isNotEmpty ? device.platformName : 'Connected BLE device';
        _addDevice(EegDevice(
          name: name,
          id: device.remoteId.toString(),
          kind: _kindForName(name),
          isBle: true,
        ));
      }
    } catch (e) {
      debugPrint('[BLE systemDevices scan error] $e');
    }

    await _bleScanSub?.cancel();
    _bleScanSub = ble.FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final name = result.device.platformName.isNotEmpty
            ? result.device.platformName
            : result.advertisementData.advName;
        final device = EegDevice(
          name: name.isEmpty ? 'Unknown BLE device' : name,
          id: result.device.remoteId.toString(),
          kind: _kindForName(name),
          isBle: true,
        );
        _addDevice(device);
      }
    });

    // We run classic scan only on Android as it's not supported on iOS
    if (Platform.isAndroid) {
      await _classicScanSub?.cancel();
      try {
        _classicScanSub = classic.FlutterBluetoothSerial.instance
            .startDiscovery()
            .listen((result) {
              _addDevice(
                EegDevice(
                  name: result.device.name ?? 'Unknown classic device',
                  id: result.device.address,
                  kind: _kindForName(result.device.name ?? ''),
                  isBle: false,
                ),
              );
            });
      } catch (e) {
        debugPrint('[Classic Bluetooth scan error] $e');
      }
    }

    try {
      await ble.FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
        continuousUpdates: true,
        androidCheckLocationServices: false,
      );
    } catch (e) {
      debugPrint('[BLE scan error] $e');
    }

    Future<void>.delayed(const Duration(seconds: 9), () async {
      if (_currentState == AcquisitionState.scanning) {
        await stopScan();
        _setState(AcquisitionState.disconnected);
      }
    });
  }

  Future<void> stopScan() async {
    await _classicScanSub?.cancel();
    _classicScanSub = null;
    await _bleScanSub?.cancel();
    _bleScanSub = null;
    try {
      if (ble.FlutterBluePlus.isScanningNow) {
        await ble.FlutterBluePlus.stopScan();
      }
    } catch (e) {
      debugPrint('[BLE stop scan error] $e');
    }
  }

  Future<void> connect(EegDevice device) async {
    await stopScan();
    await disconnect();
    _setState(AcquisitionState.connecting);

    if (device.kind == DeviceKind.synthetic) {
      _startSynthetic();
      return;
    }
    if (device.isBle) {
      await _connectBle(device);
    } else {
      await _connectClassic(device);
    }
  }

  Future<void> disconnect() async {
    _syntheticTimer?.cancel();
    _syntheticTimer = null;
    await _classicInputSub?.cancel();
    await _classicConnection?.close();
    _classicConnection = null;
    await _bleNotifySub?.cancel();
    await _bleDevice?.disconnect();
    _bleDevice = null;
    _classicBuffer.clear();
    _bleBuffer.clear();
    _orbitTextBuffer = '';
    _setState(AcquisitionState.disconnected);
  }

  void dispose() {
    unawaited(disconnect());
    _state.close();
    _samples.close();
    _devices.close();
  }

  void addSyntheticDevice() {
    _addDevice(
      const EegDevice(
        name: 'Synthetic frontal EEG',
        id: 'synthetic',
        kind: DeviceKind.synthetic,
        isBle: false,
      ),
    );
  }

  Future<void> _connectClassic(EegDevice device) async {
    _classicConnection = await classic.BluetoothConnection.toAddress(device.id);
    _classicInputSub = _classicConnection!.input?.listen((data) {
      if (device.kind == DeviceKind.epidome) {
        _parseEpiDomeBytes(data);
      } else {
        _parseAsciiOrbit(data);
      }
    });
    _setState(AcquisitionState.streaming);
  }

  Future<void> _connectBle(EegDevice device) async {
    _bleDevice = ble.BluetoothDevice.fromId(device.id);
    await _bleDevice!.connect(
      license: ble.License.nonprofit,
      timeout: const Duration(seconds: 12),
      autoConnect: false,
    );
    final services = await _bleDevice!.discoverServices();
    final characteristics = services
        .expand((service) => service.characteristics)
        .toList();
    
    final pair = device.kind == DeviceKind.epidome
        ? _selectEpiDomeCharacteristics(characteristics)
        : _selectOrbitCharacteristics(characteristics);
    final notify = pair?.notify;
    final write = pair?.write;
    
    if (notify == null) {
      throw StateError('No BLE notify characteristic found for ${device.name}');
    }
    await notify.setNotifyValue(true);
    
    if (write != null) {
      final command = device.kind == DeviceKind.epidome
          ? [0x72, 0x78, 0x73, 0x37]
          : utf8.encode('9');
      final withoutResponse =
          write.properties.writeWithoutResponse && !write.properties.write;
      await write.write(command, withoutResponse: withoutResponse);
    }
    
    _bleNotifySub = notify.onValueReceived.listen((data) {
      if (device.kind == DeviceKind.epidome) {
        _parseEpiDomeBytes(Uint8List.fromList(data), bleSource: true);
      } else {
        _parseOrbitBleBytes(data);
      }
    });
    _setState(AcquisitionState.streaming);
  }

  void _parseEpiDomeBytes(Uint8List data, {bool bleSource = false}) {
    final buffer = bleSource ? _bleBuffer : _classicBuffer;
    buffer.addAll(data);
    const header = 0xAA;
    const frameLength = 51;
    while (buffer.length >= frameLength) {
      final start = buffer.indexOf(header);
      if (start < 0) {
        buffer.clear();
        return;
      }
      if (start > 0) {
        buffer.removeRange(0, start);
      }
      if (buffer.length < frameLength) return;
      final payload = buffer.sublist(3, frameLength);
      final channels = <double>[];
      for (var i = 0; i + 2 < payload.length && channels.length < 16; i += 3) {
        var raw = payload[i] | (payload[i + 1] << 8) | (payload[i + 2] << 16);
        if ((raw & 0x800000) != 0) raw -= 0x1000000;
        channels.add(raw * -0.0224);
      }
      buffer.removeRange(0, frameLength);
      if (channels.isNotEmpty) {
        _samples.add(
          EegSample(
            channels: channels,
            sampleRate: 250,
            timestamp: DateTime.now(),
            source: 'EpiDome/xAMP-L10',
          ),
        );
      }
    }
  }

  void _parseAsciiOrbit(Uint8List data, {bool bleSource = false}) {
    final buffer = bleSource ? _bleBuffer : _classicBuffer;
    buffer.addAll(data);
    while (buffer.contains(10)) {
      final end = buffer.indexOf(10);
      final line = String.fromCharCodes(buffer.sublist(0, end)).trim();
      buffer.removeRange(0, end + 1);
      final values = line
          .split(RegExp(r'[\s,;]+'))
          .map(double.tryParse)
          .whereType<double>()
          .toList(growable: false);
      if (values.isNotEmpty) {
        _samples.add(
          EegSample(
            channels: values.take(2).toList(),
            sampleRate: 250,
            timestamp: DateTime.now(),
            source: 'Orbit',
          ),
        );
      }
    }
  }

  void _parseOrbitBleBytes(List<int> data) {
    _orbitTextBuffer += utf8.decode(data, allowMalformed: true);
    while (true) {
      final start = _orbitTextBuffer.indexOf('{');
      if (start < 0) {
        if (_orbitTextBuffer.length > 500) _orbitTextBuffer = '';
        return;
      }
      final end = _orbitTextBuffer.indexOf('}', start);
      if (end < 0) return;
      final packet = _orbitTextBuffer.substring(start, end + 1);
      _orbitTextBuffer = _orbitTextBuffer.substring(end + 1);
      try {
        final normalized = packet.replaceAllMapped(
          RegExp(r'([\{,]\s*)([A-Za-z]+)(\s*:)'),
          (match) => '${match.group(1)}"${match.group(2)}"${match.group(3)}',
        );
        final json = jsonDecode(normalized) as Map<String, dynamic>;
        final a = _numberList(json['A']);
        final b = _numberList(json['B']);
        final count = min(a.length, b.length);
        for (var i = 0; i < count; i++) {
          _samples.add(
            EegSample(
              channels: [-0.0224 * a[i], -0.0224 * b[i]],
              sampleRate: 250,
              timestamp: DateTime.now(),
              source: 'Orbit',
            ),
          );
        }
      } catch (error) {
        debugPrint('[Orbit parse] $error');
      }
    }
  }

  List<double> _numberList(Object? value) {
    if (value is List) {
      return value.whereType<num>().map((entry) => entry.toDouble()).toList();
    }
    if (value is num) return [value.toDouble()];
    return const [];
  }

  ({ble.BluetoothCharacteristic? write, ble.BluetoothCharacteristic notify})?
  _selectEpiDomeCharacteristics(
    List<ble.BluetoothCharacteristic> characteristics,
  ) {
    ble.BluetoothCharacteristic? find(String suffix) {
      for (final characteristic in characteristics) {
        if (characteristic.characteristicUuid.toString().toLowerCase().contains(
          suffix,
        )) {
          return characteristic;
        }
      }
      return null;
    }

    final write = find('f000c0c1-0451-4000-b000-000000000000');
    final notify = find('f000c0c2-0451-4000-b000-000000000000');
    if (write != null && notify != null) {
      return (write: write, notify: notify);
    }
    return _selectNonStandardPair(characteristics);
  }

  ({ble.BluetoothCharacteristic? write, ble.BluetoothCharacteristic notify})?
  _selectOrbitCharacteristics(
    List<ble.BluetoothCharacteristic> characteristics,
  ) {
    return _selectNonStandardPair(characteristics);
  }

  ({ble.BluetoothCharacteristic? write, ble.BluetoothCharacteristic notify})?
  _selectNonStandardPair(List<ble.BluetoothCharacteristic> characteristics) {
    final byService = <String, List<ble.BluetoothCharacteristic>>{};
    for (final characteristic in characteristics) {
      final service = characteristic.serviceUuid.toString().toLowerCase();
      if (service.contains('00001800-') ||
          service.contains('00001801-') ||
          service.contains('0000180f-')) {
        continue;
      }
      byService.putIfAbsent(service, () => []).add(characteristic);
    }
    for (final entries in byService.values) {
      final write = entries
          .where(
            (entry) =>
                entry.properties.write || entry.properties.writeWithoutResponse,
          )
          .firstOrNull;
      final notify = entries
          .where(
            (entry) => entry.properties.notify || entry.properties.indicate,
          )
          .firstOrNull;
      if (write != null && notify != null) {
        return (write: write, notify: notify);
      }
    }
    return null;
  }

  void _startSynthetic() {
    _setState(AcquisitionState.streaming);
    _syntheticTimer = Timer.periodic(const Duration(milliseconds: 4), (_) {
      // Periodic timer running at ~250 Hz (4ms) to generate synthetic frontal EEG values
      final stageCycle = (_syntheticT / 30).floor() % 4;
      final baseFreq = switch (stageCycle) {
        0 => 10.0, // Alpha
        1 => 6.0,  // Theta
        2 => 2.0,  // Delta
        _ => 14.0, // Beta
      };
      final amp = stageCycle == 2 ? 80.0 : 30.0;
      final sample =
          amp * sin(2 * pi * baseFreq * _syntheticT) +
          _random.nextDouble() * 10.0 -
          5.0;
      _samples.add(
        EegSample(
          channels: [sample, -sample * 0.5], // Simulate 2 channels
          sampleRate: 250,
          timestamp: DateTime.now(),
          source: 'Synthetic',
        ),
      );
      _syntheticT += 0.004;
    });
  }

  DeviceKind _kindForName(String name) {
    final upper = name.toUpperCase();
    if (upper.contains('ORBIT')) return DeviceKind.orbit;
    if (upper.contains('EPIDOME') ||
        upper.contains('XAMP') ||
        upper.contains('AXXSPU')) {
      return DeviceKind.epidome;
    }
    return DeviceKind.orbit;
  }

  void _addDevice(EegDevice device) {
    // If the device is an EEG device (ORBIT_ or AXXSPU/EPIDOME/xAMP), force isBle to true
    final nameUpper = device.name.toUpperCase();
    final isEegDevice = nameUpper.contains('ORBIT') ||
                        nameUpper.contains('EPIDOME') ||
                        nameUpper.contains('XAMP') ||
                        nameUpper.contains('AXXSPU');
    
    final normalizedDevice = isEegDevice
        ? EegDevice(
            name: device.name,
            id: device.id,
            kind: device.kind,
            isBle: true,
          )
        : device;

    final existing = _seenDevices.indexWhere((entry) => entry.id == normalizedDevice.id);
    if (existing >= 0) {
      final existingDevice = _seenDevices[existing];
      // Do not allow a classic scan result to downgrade an already discovered BLE device
      if (existingDevice.isBle && !normalizedDevice.isBle) {
        return;
      }
      _seenDevices[existing] = normalizedDevice;
    } else {
      _seenDevices.add(normalizedDevice);
      debugPrint('[Bluetooth scan] Added device ${normalizedDevice.name} (${normalizedDevice.id})');
    }
    _publishDevices();
  }

  void _publishDevices() {
    _devices.add(List.unmodifiable(_seenDevices));
  }

  void _setState(AcquisitionState value) {
    if (_currentState == value) return;
    _currentState = value;
    _state.add(value);
    debugPrint('[Acquisition State] $value');
  }
}
