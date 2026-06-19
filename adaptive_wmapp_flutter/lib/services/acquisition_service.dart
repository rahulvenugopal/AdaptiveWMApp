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
  String orbitPrefix = 'ORBIT_';
  String xampPrefix = 'AXXSPU00003';

  static const String _nordicUartServiceUuid =
      '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String _nordicUartRxUuid =
      '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const String _nordicUartTxUuid =
      '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
  static const String _hm10ServiceUuid = 'ffe0';
  static const String _hm10DataUuid = 'ffe1';
  static const String _tiDataStreamServiceUuid =
      'f000c0c0-0451-4000-b000-000000000000';
  static const String _tiDataStreamWriteUuid =
      'f000c0c1-0451-4000-b000-000000000000';
  static const String _tiDataStreamNotifyUuid =
      'f000c0c2-0451-4000-b000-000000000000';
  static const int _epidomeFrameHeader = 0xAA;
  static const int _epidomeFrameHeaderLength = 3;
  static const int _epidomeChannelCount = 16;
  static const int _epidomeFrameLength =
      _epidomeFrameHeaderLength + _epidomeChannelCount * 3;
  static const double _ads1299UvPerCount = -0.0224;

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
  StreamSubscription<ble.BluetoothConnectionState>? _bleConnectionStateSub;

  // Reconnect settings and state
  int reconnectMaxAttempts = 10;
  int _reconnectAttempts = 0;
  EegDevice? _lastConnectedDevice;
  bool _autoReconnectEnabled = false;
  Timer? _reconnectTimer;
  final _maxRetriesReachedController = StreamController<void>.broadcast();

  Stream<void> get maxRetriesReached => _maxRetriesReachedController.stream;
  classic.BluetoothConnection? _classicConnection;
  ble.BluetoothDevice? _bleDevice;
  Timer? _syntheticTimer;
  double _syntheticT = 0.0;

  Stream<AcquisitionState> get state => _state.stream;
  Stream<EegSample> get samples => _samples.stream;
  Stream<List<EegDevice>> get devices => _devices.stream;
  AcquisitionState get currentState => _currentState;

  int get channelCount {
    if (_lastConnectedDevice == null) return 0;
    if (_lastConnectedDevice!.kind == DeviceKind.orbit) return 2;
    return 16;
  }

  double get sampleRate {
    if (_lastConnectedDevice == null) return 0.0;
    return 250.0;
  }

  String? get connectedDeviceName => _lastConnectedDevice?.name;

  Future<void> requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      Permission.storage,
      Permission.manageExternalStorage,
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
        final name = device.platformName.isNotEmpty
            ? device.platformName
            : 'Connected BLE device';
        _addDevice(
          EegDevice(
            name: name,
            id: device.remoteId.toString(),
            kind: _kindForName(name),
            isBle: true,
          ),
        );
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
              final name = result.device.name ?? 'Unknown classic device';
              if (_matchesXampPrefix(name)) return;
              _addDevice(
                EegDevice(
                  name: name,
                  id: result.device.address,
                  kind: _kindForName(name),
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

    try {
      if (device.kind == DeviceKind.synthetic) {
        _startSynthetic();
      } else if (device.isBle) {
        await _connectBle(device);
      } else {
        await _connectClassic(device);
      }
      _lastConnectedDevice = device;
      _autoReconnectEnabled = true;
      _reconnectAttempts = 0;
    } catch (e) {
      _setState(AcquisitionState.disconnected);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _autoReconnectEnabled = false;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    await _bleConnectionStateSub?.cancel();
    _bleConnectionStateSub = null;

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
    _maxRetriesReachedController.close();
  }

  void _handleUnexpectedDisconnect() {
    if (!_autoReconnectEnabled || _currentState != AcquisitionState.streaming) {
      return;
    }
    debugPrint('[AcquisitionService] Unexpected disconnect detected!');
    _setState(AcquisitionState.disconnected);
    _startReconnectTimer();
  }

  void _startReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      _reconnectAttempts++;
      if (reconnectMaxAttempts > 0 && _reconnectAttempts > reconnectMaxAttempts) {
        _stopReconnectTimer();
        _maxRetriesReachedController.add(null);
        return;
      }
      if (_lastConnectedDevice == null || !_autoReconnectEnabled) {
        _stopReconnectTimer();
        return;
      }

      debugPrint('[AcquisitionService] Auto-reconnect attempt $_reconnectAttempts'
          '${reconnectMaxAttempts > 0 ? '/$reconnectMaxAttempts' : ''}: '
          'connecting to ${_lastConnectedDevice!.name}');

      try {
        await connect(_lastConnectedDevice!);
        debugPrint('[AcquisitionService] Auto-reconnect successful!');
      } catch (e) {
        debugPrint('[AcquisitionService] Auto-reconnect failed: $e');
        _setState(AcquisitionState.disconnected);
      }
    });
  }

  void _stopReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
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
    _classicInputSub = _classicConnection!.input?.listen(
      (data) {
        if (device.kind == DeviceKind.epidome) {
          _parseEpiDomeBytes(data);
        } else {
          _parseAsciiOrbit(data);
        }
      },
      onDone: () => _handleUnexpectedDisconnect(),
      onError: (e) => _handleUnexpectedDisconnect(),
    );
    _setState(AcquisitionState.streaming);
  }

  Future<void> _connectBle(EegDevice device) async {
    _bleDevice = ble.BluetoothDevice.fromId(device.id);

    await _bleConnectionStateSub?.cancel();
    _bleConnectionStateSub = _bleDevice!.connectionState.listen((connectionState) {
      if (connectionState == ble.BluetoothConnectionState.disconnected) {
        _handleUnexpectedDisconnect();
      }
    });

    await _bleDevice!.connect(
      license: ble.License.nonprofit,
      timeout: const Duration(seconds: 12),
      autoConnect: false,
    );
    try {
      await _bleDevice!.requestMtu(247, predelay: 0);
    } catch (error) {
      debugPrint('[BLE Bluetooth] MTU request skipped/failed: $error');
    }
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

    _bleNotifySub = notify.onValueReceived.listen(
      (data) {
        if (device.kind == DeviceKind.epidome) {
          _parseEpiDomeBytes(Uint8List.fromList(data), bleSource: true);
        } else {
          _parseOrbitBleBytes(data);
        }
      },
      onError: (e) => _handleUnexpectedDisconnect(),
      onDone: () => _handleUnexpectedDisconnect(),
    );
    _setState(AcquisitionState.streaming);
  }

  void _parseEpiDomeBytes(Uint8List data, {bool bleSource = false}) {
    final buffer = bleSource ? _bleBuffer : _classicBuffer;
    buffer.addAll(data);
    while (buffer.length >= _epidomeFrameHeaderLength) {
      final start = _findEpiDomeFrameHeader(buffer);
      if (start < 0) {
        final keepTrailing = buffer.reversed
            .takeWhile((byte) => byte == _epidomeFrameHeader)
            .length
            .clamp(0, _epidomeFrameHeaderLength - 1);
        final trailing = keepTrailing == 0
            ? const <int>[]
            : buffer.sublist(buffer.length - keepTrailing);
        buffer.clear();
        buffer.addAll(trailing);
        return;
      }
      if (start > 0) {
        buffer.removeRange(0, start);
      }
      if (buffer.length < _epidomeFrameLength) return;
      final channels = List<double>.filled(_epidomeChannelCount, 0.0);
      for (var i = 0; i < _epidomeChannelCount; i++) {
        final offset = _epidomeFrameHeaderLength + i * 3;
        var raw =
            (buffer[offset] << 16) |
            (buffer[offset + 1] << 8) |
            buffer[offset + 2];
        if ((raw & 0x800000) != 0) raw -= 0x1000000;
        channels[i] = raw * _ads1299UvPerCount;
      }
      buffer.removeRange(0, _epidomeFrameLength);
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

  int _findEpiDomeFrameHeader(List<int> buffer) {
    for (var i = 0; i <= buffer.length - _epidomeFrameHeaderLength; i++) {
      if (buffer[i] == _epidomeFrameHeader &&
          buffer[i + 1] == _epidomeFrameHeader &&
          buffer[i + 2] == _epidomeFrameHeader) {
        return i;
      }
    }
    return -1;
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
    bool canWrite(ble.BluetoothCharacteristic c) =>
        c.properties.write || c.properties.writeWithoutResponse;
    bool canNotify(ble.BluetoothCharacteristic c) =>
        c.properties.notify || c.properties.indicate;

    ble.BluetoothCharacteristic? find(String suffix) {
      final target = suffix.toLowerCase();
      for (final characteristic in characteristics) {
        final uuid = characteristic.characteristicUuid.toString().toLowerCase();
        if (uuid == target || uuid.endsWith('-$target')) {
          return characteristic;
        }
      }
      return null;
    }

    final nordicWrite = find(_nordicUartRxUuid);
    final nordicNotify = find(_nordicUartTxUuid);
    if (nordicWrite != null &&
        nordicNotify != null &&
        canWrite(nordicWrite) &&
        canNotify(nordicNotify)) {
      return (write: nordicWrite, notify: nordicNotify);
    }

    final hm10Data = find(_hm10DataUuid);
    if (hm10Data != null && canWrite(hm10Data) && canNotify(hm10Data)) {
      return (write: hm10Data, notify: hm10Data);
    }

    final write = find(_tiDataStreamWriteUuid);
    final notify = find(_tiDataStreamNotifyUuid);
    if (write != null &&
        notify != null &&
        canWrite(write) &&
        canNotify(notify)) {
      return (write: write, notify: notify);
    }

    for (final serviceUuid in [
      _nordicUartServiceUuid,
      _hm10ServiceUuid,
      _tiDataStreamServiceUuid,
    ]) {
      final serviceChars = characteristics.where((c) {
        final uuid = c.serviceUuid.toString().toLowerCase();
        return uuid == serviceUuid || uuid.endsWith('-$serviceUuid');
      }).toList();
      if (serviceChars.isEmpty) continue;
      final serviceWrite = serviceChars.where(canWrite).firstOrNull;
      final serviceNotify = serviceChars.where(canNotify).firstOrNull;
      if (serviceWrite != null && serviceNotify != null) {
        return (write: serviceWrite, notify: serviceNotify);
      }
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
        1 => 6.0, // Theta
        2 => 2.0, // Delta
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
    if (orbitPrefix.isNotEmpty && upper.startsWith(orbitPrefix.toUpperCase())) {
      return DeviceKind.orbit;
    }
    if (_matchesXampPrefix(name) ||
        upper.contains('EPIDOME') ||
        upper.contains('XAMP') ||
        upper.contains('AXXSPU')) {
      return DeviceKind.epidome;
    }
    return DeviceKind.orbit;
  }

  void _addDevice(EegDevice device) {
    final existing = _seenDevices.indexWhere((entry) => entry.id == device.id);
    if (existing >= 0) {
      final existingDevice = _seenDevices[existing];
      if (existingDevice.isBle && !device.isBle) {
        return;
      }
      _seenDevices[existing] = device;
    } else {
      _seenDevices.add(device);
      debugPrint('[Bluetooth scan] Added device ${device.name} (${device.id})');
    }
    _publishDevices();
  }

  bool _matchesXampPrefix(String name) {
    final prefix = xampPrefix.trim().toUpperCase();
    if (prefix.isEmpty) return false;
    return name.toUpperCase().startsWith(prefix);
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
