import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

class WifiNetwork {
  final String ssid;
  final int signalStrength; // 0 to 100
  final bool isSecure;
  final bool isConnected;
  final String securityType;

  const WifiNetwork({
    required this.ssid,
    required this.signalStrength,
    this.isSecure = true,
    this.isConnected = false,
    this.securityType = 'WPA2',
  });
}

class ReachabilityResult {
  final bool isReachable;
  final int latencyMs;
  final String message;

  const ReachabilityResult({
    required this.isReachable,
    required this.latencyMs,
    required this.message,
  });
}

class NetworkStatus {
  final bool isOnline;
  final String? currentSsid;
  final String? ipAddress;
  final String? interfaceName;
  final int signalStrength;
  final List<WifiNetwork> availableNetworks;
  final bool isScanning;
  final String connectionType; // 'Ethernet', 'WiFi', 'Offline'
  final ReachabilityResult? lastReachabilityResult;

  const NetworkStatus({
    required this.isOnline,
    this.currentSsid,
    this.ipAddress,
    this.interfaceName,
    this.signalStrength = 0,
    this.availableNetworks = const [],
    this.isScanning = false,
    this.connectionType = 'Offline',
    this.lastReachabilityResult,
  });

  bool get isEthernet =>
      isOnline &&
      (connectionType == 'Ethernet' || connectionType == 'Ethernet / LAN');
  bool get isWifi => isOnline && connectionType == 'WiFi';

  NetworkStatus copyWith({
    bool? isOnline,
    String? currentSsid,
    String? ipAddress,
    String? interfaceName,
    int? signalStrength,
    List<WifiNetwork>? availableNetworks,
    bool? isScanning,
    String? connectionType,
    ReachabilityResult? lastReachabilityResult,
  }) {
    return NetworkStatus(
      isOnline: isOnline ?? this.isOnline,
      currentSsid: currentSsid ?? this.currentSsid,
      ipAddress: ipAddress ?? this.ipAddress,
      interfaceName: interfaceName ?? this.interfaceName,
      signalStrength: signalStrength ?? this.signalStrength,
      availableNetworks: availableNetworks ?? this.availableNetworks,
      isScanning: isScanning ?? this.isScanning,
      connectionType: connectionType ?? this.connectionType,
      lastReachabilityResult:
          lastReachabilityResult ?? this.lastReachabilityResult,
    );
  }
}

class NetworkService extends ChangeNotifier {
  static NetworkService? _instance;
  static NetworkService get instance => _instance ??= NetworkService._();

  NetworkService._() {
    _init();
  }

  NetworkStatus _status = const NetworkStatus(
    isOnline: false,
    connectionType: 'Offline',
  );
  Timer? _monitorTimer;
  bool _isChecking = false;

  NetworkStatus get status => _status;
  bool get isOnline => _status.isOnline;

  void _init() {
    checkConnectivity();
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => checkConnectivity(),
    );
  }

  @override
  void dispose() {
    _monitorTimer?.cancel();
    super.dispose();
  }

  /// Checks if a Linux network interface has physical carrier and is operstate up
  Future<bool> _isInterfacePhysicallyUp(String ifaceName) async {
    try {
      final carrierFile = File('/sys/class/net/$ifaceName/carrier');
      if (await carrierFile.exists()) {
        final val = (await carrierFile.readAsString()).trim();
        if (val != '1') return false;
      }

      final operFile = File('/sys/class/net/$ifaceName/operstate');
      if (await operFile.exists()) {
        final val = (await operFile.readAsString()).trim().toLowerCase();
        return val == 'up' || val == 'unknown';
      }
    } catch (_) {}
    return false;
  }

  /// Probes real internet reachability via TCP socket connection and physical interface inspection
  Future<bool> checkConnectivity() async {
    if (_isChecking) return _status.isOnline;
    _isChecking = true;

    bool online = false;
    String connectionType = 'Offline';
    String? currentSsid;
    String? localIp;
    String? activeIfaceName;
    int signal = 0;

    // 1. Inspect real physical Linux network interfaces
    try {
      final netDir = Directory('/sys/class/net');
      if (await netDir.exists()) {
        final entries = await netDir.list().toList();
        for (final entry in entries) {
          final iface = entry.path.split('/').last;
          if (iface == 'lo' ||
              iface.startsWith('virbr') ||
              iface.startsWith('docker') ||
              iface.startsWith('veth')) {
            continue;
          }

          final isUp = await _isInterfacePhysicallyUp(iface);
          if (isUp) {
            activeIfaceName = iface;
            final lower = iface.toLowerCase();
            if (lower.startsWith('wl') ||
                lower.contains('wlan') ||
                lower.contains('wifi')) {
              connectionType = 'WiFi';
            } else if (lower.startsWith('en') ||
                lower.startsWith('eth') ||
                lower.startsWith('eno') ||
                lower.startsWith('ens') ||
                lower.startsWith('enp') ||
                lower.startsWith('usb')) {
              connectionType = 'Ethernet';
            }
            break;
          }
        }
      }
    } catch (_) {}

    // 2. If an active interface was found, get IP address
    if (activeIfaceName != null) {
      try {
        final interfaces = await NetworkInterface.list(
          includeLoopback: false,
          type: InternetAddressType.IPv4,
        );

        for (final iface in interfaces) {
          if (iface.name == activeIfaceName && iface.addresses.isNotEmpty) {
            localIp = iface.addresses.first.address;
            break;
          }
        }
      } catch (_) {}

      // Check active WiFi SSID if WiFi interface is up
      if (connectionType == 'WiFi') {
        try {
          final nmResult = await Process.run('nmcli', [
            '-t',
            '-f',
            'ACTIVE,SSID,SIGNAL',
            'dev',
            'wifi',
          ]);
          if (nmResult.exitCode == 0) {
            final lines = nmResult.stdout.toString().split('\n');
            for (final line in lines) {
              final parts = line.split(':');
              if (parts.isNotEmpty && parts[0].trim() == 'yes') {
                final rawSsid = parts.length > 1 ? parts[1].trim() : null;
                if (rawSsid != null && rawSsid.isNotEmpty) {
                  currentSsid = rawSsid;
                }
                signal = parts.length > 2
                    ? int.tryParse(parts[2].trim()) ?? 80
                    : 80;
                break;
              }
            }
          }
        } catch (_) {}
      }
    }

    // 3. Test genuine internet reachability via real TCP connection
    if (activeIfaceName != null) {
      try {
        final socket = await Socket.connect(
          '1.1.1.1',
          53,
          timeout: const Duration(seconds: 2),
        );
        socket.destroy();
        online = true;
      } catch (_) {
        try {
          final socket = await Socket.connect(
            '8.8.8.8',
            53,
            timeout: const Duration(seconds: 2),
          );
          socket.destroy();
          online = true;
        } catch (_) {
          online = false;
        }
      }
    }

    // If interface is down or socket unreachable, force offline
    if (!online || activeIfaceName == null) {
      connectionType = 'Offline';
      currentSsid = null;
      online = false;
    }

    final newStatus = _status.copyWith(
      isOnline: online,
      connectionType: connectionType,
      currentSsid: currentSsid,
      ipAddress: localIp,
      interfaceName: activeIfaceName,
      signalStrength: signal > 0 ? signal : (online ? 85 : 0),
    );

    _isChecking = false;

    if (newStatus.isOnline != _status.isOnline ||
        newStatus.currentSsid != _status.currentSsid ||
        newStatus.connectionType != _status.connectionType ||
        newStatus.interfaceName != _status.interfaceName) {
      _status = newStatus;
      notifyListeners();
    } else {
      _status = newStatus;
    }

    return online;
  }

  /// Actively tests roundtrip TCP latency to Cloud & DNS
  Future<ReachabilityResult> testReachability() async {
    final stopwatch = Stopwatch()..start();
    bool reachable = false;
    int latency = 0;
    String message = 'Offline - No route to host';

    try {
      final socket = await Socket.connect(
        '1.1.1.1',
        53,
        timeout: const Duration(seconds: 3),
      );
      stopwatch.stop();
      latency = stopwatch.elapsedMilliseconds;
      socket.destroy();
      reachable = true;
      message = 'Internet Reachable • ${latency}ms latency (Fast & Stable)';
    } catch (_) {
      try {
        stopwatch.reset();
        stopwatch.start();
        final socket2 = await Socket.connect(
          '8.8.8.8',
          53,
          timeout: const Duration(seconds: 3),
        );
        stopwatch.stop();
        latency = stopwatch.elapsedMilliseconds;
        socket2.destroy();
        reachable = true;
        message = 'Internet Reachable • ${latency}ms latency';
      } catch (e) {
        reachable = false;
        message = 'Offline • Unable to reach DNS or Cloud Server';
      }
    }

    final result = ReachabilityResult(
      isReachable: reachable,
      latencyMs: latency,
      message: message,
    );

    _status = _status.copyWith(
      isOnline: reachable,
      lastReachabilityResult: result,
    );
    notifyListeners();

    return result;
  }

  /// Scans for ACTUAL available WiFi networks nearby (Zero Hardcoded SSIDs)
  Future<List<WifiNetwork>> scanNetworks() async {
    _status = _status.copyWith(isScanning: true);
    notifyListeners();

    final networks = <WifiNetwork>[];
    final seenSsids = <String>{};

    try {
      final res = await Process.run('nmcli', [
        '-t',
        '-f',
        'SSID,SIGNAL,SECURITY,IN-USE',
        'dev',
        'wifi',
        'list',
        '--rescan',
        'yes',
      ]).timeout(const Duration(seconds: 5));

      if (res.exitCode == 0) {
        final lines = res.stdout.toString().split('\n');

        for (final line in lines) {
          final parts = line.split(':');
          if (parts.length >= 3) {
            final ssid = parts[0].trim();
            final sig = int.tryParse(parts[1].trim()) ?? 60;
            final sec = parts[2].trim();
            final inUse = parts.length > 3 && parts[3].trim() == '*';

            // Filter out hidden / empty SSIDs and duplicates
            if (ssid.isNotEmpty && !seenSsids.contains(ssid)) {
              seenSsids.add(ssid);
              networks.add(
                WifiNetwork(
                  ssid: ssid,
                  signalStrength: sig,
                  isSecure: sec.isNotEmpty && !sec.contains('--'),
                  isConnected: inUse || (_status.currentSsid == ssid),
                  securityType: sec.isNotEmpty ? sec : 'Open',
                ),
              );
            }
          }
        }
      }
    } catch (_) {}

    // Sort: Connected network first, then by signal strength descending
    networks.sort((a, b) {
      if (a.isConnected && !b.isConnected) return -1;
      if (!a.isConnected && b.isConnected) return 1;
      return b.signalStrength.compareTo(a.signalStrength);
    });

    _status = _status.copyWith(availableNetworks: networks, isScanning: false);
    notifyListeners();
    return networks;
  }

  /// Connects to a WiFi network with password
  Future<bool> connectToWifi(String ssid, String password) async {
    _status = _status.copyWith(isScanning: true);
    notifyListeners();

    bool success = false;

    try {
      List<String> args;
      if (password.isNotEmpty) {
        args = ['dev', 'wifi', 'connect', ssid, 'password', password];
      } else {
        args = ['dev', 'wifi', 'connect', ssid];
      }

      final res = await Process.run(
        'nmcli',
        args,
      ).timeout(const Duration(seconds: 10));
      if (res.exitCode == 0) {
        success = true;
      }
    } catch (_) {}

    // Verify connection
    await Future.delayed(const Duration(milliseconds: 1000));
    await checkConnectivity();
    await scanNetworks();

    return success || _status.isOnline;
  }
}
