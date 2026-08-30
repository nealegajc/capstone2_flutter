import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_helper.dart';
import '../../data/services/network_service.dart';
import '../../providers/kiosk_providers.dart';

class WifiConnectionDialog extends ConsumerStatefulWidget {
  const WifiConnectionDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => const WifiConnectionDialog(),
    );
  }

  @override
  ConsumerState<WifiConnectionDialog> createState() => _WifiConnectionDialogState();
}

class _WifiConnectionDialogState extends ConsumerState<WifiConnectionDialog> {
  final TextEditingController _passwordController = TextEditingController();
  WifiNetwork? _selectedNetwork;
  bool _obscurePassword = true;
  bool _isConnecting = false;
  bool _isTestingReachability = false;
  ReachabilityResult? _reachabilityResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(networkServiceProvider).scanNetworks();
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _onSelectNetwork(WifiNetwork network) {
    setState(() {
      _selectedNetwork = network;
      _passwordController.clear();
    });
  }

  Future<void> _runReachabilityTest() async {
    setState(() {
      _isTestingReachability = true;
      _reachabilityResult = null;
    });

    final res = await ref.read(networkServiceProvider).testReachability();

    if (mounted) {
      setState(() {
        _isTestingReachability = false;
        _reachabilityResult = res;
      });
    }
  }

  Future<void> _connectToSelected() async {
    if (_selectedNetwork == null) return;
    setState(() => _isConnecting = true);

    final netService = ref.read(networkServiceProvider);
    final success = await netService.connectToWifi(
      _selectedNetwork!.ssid,
      _passwordController.text.trim(),
    );

    if (mounted) {
      setState(() => _isConnecting = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to "${_selectedNetwork!.ssid}" successfully.'),
            backgroundColor: AppColors.statusGreen,
          ),
        );
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect to "${_selectedNetwork!.ssid}". Please check the password.'),
            backgroundColor: AppColors.statusRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final netStatus = ref.watch(networkStatusProvider);
    final isScanning = netStatus.isScanning || _isConnecting;
    final isEth = netStatus.isEthernet;

    IconData headerIcon;
    String headerSubtitle;

    if (netStatus.isOnline) {
      if (isEth) {
        headerIcon = Icons.lan_rounded;
        headerSubtitle = 'Online • Connected via Wired Ethernet LAN (${netStatus.interfaceName ?? "eth0"})';
      } else {
        headerIcon = Icons.wifi_rounded;
        headerSubtitle = 'Online • Connected via Wi-Fi (${netStatus.currentSsid ?? "Network"})';
      }
    } else {
      headerIcon = Icons.wifi_off_rounded;
      headerSubtitle = 'Offline • No active network detected';
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: context.surfaceColor,
      child: Container(
        width: 680,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: netStatus.isOnline
                            ? AppColors.statusGreen.withValues(alpha: 0.15)
                            : AppColors.statusRed.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        headerIcon,
                        color: netStatus.isOnline ? AppColors.statusGreen : AppColors.statusRed,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Network & Connectivity Settings',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        Text(
                          headerSubtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: netStatus.isOnline ? AppColors.statusGreen : AppColors.statusRed,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: isScanning
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandAccent),
                            )
                          : const Icon(Icons.refresh_rounded),
                      tooltip: 'Rescan Wi-Fi Networks',
                      onPressed: isScanning ? null : () => ref.read(networkServiceProvider).scanNetworks(),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ],
            ),
            Divider(height: 24, color: context.borderColor),

            // Active Connection Telemetry Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: context.surfaceElevatedColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: netStatus.isOnline ? AppColors.statusGreen.withValues(alpha: 0.4) : AppColors.statusRed.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isEth
                                ? Icons.lan_rounded
                                : (netStatus.isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded),
                            size: 18,
                            color: netStatus.isOnline ? AppColors.statusGreen : AppColors.statusRed,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isEth
                                ? 'Wired Ethernet Connected'
                                : (netStatus.isOnline ? 'Wi-Fi: ${netStatus.currentSsid ?? "Connected"}' : 'No Internet Connection (Offline)'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: context.textPrimaryColor,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: netStatus.isOnline ? AppColors.statusGreenBg : AppColors.statusRedBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          netStatus.isOnline ? 'Online' : 'Offline',
                          style: TextStyle(
                            color: netStatus.isOnline ? AppColors.statusGreen : AppColors.statusRed,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Interface: ${netStatus.interfaceName ?? (netStatus.isOnline ? "wlan0" : "None")} • Status: ${netStatus.connectionType}',
                        style: TextStyle(fontSize: 11, color: context.textSecondaryColor),
                      ),
                      Text(
                        'IP: ${netStatus.ipAddress ?? "Unassigned"}',
                        style: TextStyle(fontSize: 11, color: context.textSecondaryColor, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Real-Time Reachability Live Banner if tested
            if (_reachabilityResult != null)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _reachabilityResult!.isReachable
                      ? AppColors.statusGreenBg
                      : AppColors.statusRedBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _reachabilityResult!.isReachable
                        ? AppColors.statusGreen.withValues(alpha: 0.5)
                        : AppColors.statusRed.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _reachabilityResult!.isReachable
                          ? Icons.check_circle_rounded
                          : Icons.error_outline_rounded,
                      size: 18,
                      color: _reachabilityResult!.isReachable
                          ? AppColors.statusGreen
                          : AppColors.statusRed,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _reachabilityResult!.message,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _reachabilityResult!.isReachable
                              ? AppColors.statusGreen
                              : AppColors.statusRed,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'NEARBY WI-FI NETWORKS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: context.textSecondaryColor,
                    letterSpacing: 1.0,
                  ),
                ),
                if (netStatus.availableNetworks.isNotEmpty)
                  Text(
                    '${netStatus.availableNetworks.length} Networks Found',
                    style: TextStyle(fontSize: 11, color: context.textMutedColor, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Actual Scanned Network List (Zero Hardcoded Fallbacks)
            Flexible(
              child: isScanning && netStatus.availableNetworks.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(color: AppColors.brandAccent),
                            const SizedBox(height: 14),
                            Text(
                              'Scanning for actual nearby Wi-Fi networks...',
                              style: TextStyle(fontSize: 13, color: context.textSecondaryColor),
                            ),
                          ],
                        ),
                      ),
                    )
                  : netStatus.availableNetworks.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.wifi_find_rounded, size: 48, color: context.textMutedColor),
                                const SizedBox(height: 12),
                                Text(
                                  'No Wi-Fi networks detected nearby.',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: context.textPrimaryColor),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Tap the refresh icon above to scan for networks.',
                                  style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: netStatus.availableNetworks.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final net = netStatus.availableNetworks[index];
                            final isSelected = _selectedNetwork?.ssid == net.ssid;
                            final isCurrentlyConnected = net.isConnected || (netStatus.isOnline && !isEth && net.ssid == netStatus.currentSsid);

                            return Container(
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.brandAccent.withValues(alpha: 0.12) : context.surfaceElevatedColor,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.brandAccent
                                      : (isCurrentlyConnected ? AppColors.statusGreen.withValues(alpha: 0.5) : context.borderColor),
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ListTile(
                                    onTap: () => _onSelectNetwork(net),
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                                    leading: Icon(
                                      _getWifiIcon(net.signalStrength),
                                      color: isCurrentlyConnected ? AppColors.statusGreen : context.textPrimaryColor,
                                      size: 22,
                                    ),
                                    title: Row(
                                      children: [
                                        Text(
                                          net.ssid,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                            color: context.textPrimaryColor,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (isCurrentlyConnected)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.statusGreenBg,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              'Connected',
                                              style: TextStyle(
                                                color: AppColors.statusGreen,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      '${net.securityType} • Signal ${net.signalStrength}%',
                                      style: TextStyle(fontSize: 11, color: context.textSecondaryColor),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (net.isSecure)
                                          Icon(Icons.lock_rounded, size: 16, color: context.textMutedColor),
                                        const SizedBox(width: 8),
                                        Icon(
                                          isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                                          color: isSelected ? AppColors.brandAccent : context.textMutedColor,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Password input section when selected
                                  if (isSelected && !isCurrentlyConnected)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 14, right: 14, bottom: 12, top: 4),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: _passwordController,
                                              obscureText: _obscurePassword,
                                              style: TextStyle(color: context.textPrimaryColor, fontSize: 13),
                                              decoration: InputDecoration(
                                                hintText: 'Enter Wi-Fi Password',
                                                filled: true,
                                                fillColor: context.surfaceColor,
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(10),
                                                  borderSide: BorderSide(color: context.borderColor),
                                                ),
                                                suffixIcon: IconButton(
                                                  icon: Icon(
                                                    _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                                    size: 18,
                                                  ),
                                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          ElevatedButton.icon(
                                            onPressed: _isConnecting ? null : _connectToSelected,
                                            icon: _isConnecting
                                                ? const SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                                  )
                                                : const Icon(Icons.link_rounded, size: 16),
                                            label: Text(_isConnecting ? 'Connecting...' : 'Connect'),
                                            style: ElevatedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
            ),

            const SizedBox(height: 16),

            // Bottom Buttons: Test Reachability & Done
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton.icon(
                  onPressed: _isTestingReachability ? null : _runReachabilityTest,
                  icon: _isTestingReachability
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandAccent),
                        )
                      : const Icon(Icons.speed_rounded, size: 16),
                  label: Text(_isTestingReachability ? 'Pinging Cloud...' : 'Test Reachability (Ping)'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getWifiIcon(int signal) {
    if (signal >= 75) return Icons.wifi_rounded;
    if (signal >= 50) return Icons.wifi_2_bar_rounded;
    if (signal >= 25) return Icons.wifi_1_bar_rounded;
    return Icons.wifi_off_rounded;
  }
}
