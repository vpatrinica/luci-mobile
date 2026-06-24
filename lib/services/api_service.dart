import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import '../utils/http_client_manager.dart';
import '../utils/logger.dart';

class LoginResult {
  final String? token;
  final bool actualUseHttps;

  LoginResult({required this.token, required this.actualUseHttps});
}

Uri _buildUrl(String ipAddress, bool useHttps, String path) {
  final scheme = useHttps ? 'https' : 'http';
  // Handle cases where ipAddress might already include a port
  String host = ipAddress;
  // Don't add scheme if the address already has one (shouldn't happen with our parser)
  if (host.startsWith('http://') || host.startsWith('https://')) {
    return Uri.parse('$host$path');
  }
  return Uri.parse('$scheme://$host$path');
}

class RealApiService implements IApiService {
  final HttpClientManager _httpClientManager = HttpClientManager();

  Dio _createHttpClient(
    bool useHttps,
    String hostWithPort, {
    BuildContext? context,
  }) {
    return _httpClientManager.getClient(
      hostWithPort,
      useHttps,
      context: context,
    );
  }

  @override
  Future<String> login(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  }) async {
    final result = await loginWithProtocolDetection(
      ipAddress,
      username,
      password,
      useHttps,
      context: context,
    );
    if (result.token == null) {
      throw Exception('Login failed');
    }
    return result.token!;
  }

  /// Login with automatic HTTPS redirect detection
  /// Returns both the auth token and the actual protocol used
  Future<LoginResult> loginWithProtocolDetection(
    String ipAddress,
    String username,
    String password,
    bool initialUseHttps, {
    BuildContext? context,
  }) async {
    // First try with the initial protocol
    var result = await _login(
      ipAddress,
      username,
      password,
      initialUseHttps,
      context: context,
      checkRedirect: true,
    );

    // Check if we got a redirect marker
    if (result != null && result.startsWith('HTTPS_REDIRECT:')) {
      final token = result.substring('HTTPS_REDIRECT:'.length);
      Logger.info('Login successful via HTTP to HTTPS redirect');
      return LoginResult(token: token, actualUseHttps: true);
    }

    if (result != null) {
      return LoginResult(token: result, actualUseHttps: initialUseHttps);
    }

    // If login failed and we were using HTTP, try HTTPS in case of redirect
    if (!initialUseHttps) {
      Logger.info('HTTP login failed or redirected, attempting HTTPS');
      final safeContext = context?.mounted == true ? context : null;
      result = await _login(
        ipAddress,
        username,
        password,
        true, // Try with HTTPS
        context: safeContext, // ignore: use_build_context_synchronously
        checkRedirect: false,
      );

      if (result != null) {
        Logger.info('Login successful with HTTPS after redirect detection');
        return LoginResult(token: result, actualUseHttps: true);
      }
    }

    return LoginResult(token: null, actualUseHttps: initialUseHttps);
  }

  /// RUTOS login via POST /api/login with JSON credentials.
  /// Returns the session token string, or a 'HTTPS_REDIRECT:<token>' marker
  /// when an HTTP→HTTPS redirect was detected.
  Future<String?> _login(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
    bool checkRedirect = false,
  }) async {
    final client = _createHttpClient(useHttps, ipAddress, context: context);
    final uri = _buildUrl(ipAddress, useHttps, '/api/login');

    try {
      final response = await client.post(
        uri.toString(),
        data: jsonEncode({'username': username, 'password': password}),
        options: Options(
          headers: {'Content-Type': 'application/json'},
          followRedirects: false,
          validateStatus: (code) => code != null && code >= 200 && code < 500,
        ),
      );

      // Detect HTTP→HTTPS redirect via Location header or realUri scheme change
      if (checkRedirect && !useHttps) {
        final location = response.headers.value('location') ?? '';
        final redirectedToHttps =
            location.toLowerCase().startsWith('https://') ||
            response.realUri.scheme == 'https';
        if (redirectedToHttps) {
          Logger.info('Detected HTTP→HTTPS redirect via /api/login: $uri');
          // Try to parse a token from this response; otherwise signal redirect
          final token = _parseRutosToken(response.data);
          return token != null ? 'HTTPS_REDIRECT:$token' : 'HTTPS_REDIRECT:';
        }
      }

      final token = _parseRutosToken(response.data);
      return token;
    } on DioException catch (e, stack) {
      Logger.exception('RUTOS /api/login failed', e, stack);

      final isCertError =
          e.error is HandshakeException ||
          e.message?.contains('CERTIFICATE_VERIFY_FAILED') == true;

      if (!useHttps && checkRedirect && isCertError) {
        Logger.info('Cert error on HTTP attempt; retrying with HTTPS');
        final retryContext = context?.mounted == true ? context : null;
        try {
          return await _login(
            ipAddress,
            username,
            password,
            true,
            context: retryContext, // ignore: use_build_context_synchronously
            checkRedirect: false,
          );
        } on DioException catch (httpsError, httpsStack) {
          Logger.exception('HTTPS retry failed', httpsError, httpsStack);
        }
      }

      if (useHttps && context != null && context.mounted && isCertError) {
        final accepted = await _httpClientManager.promptForCertificateAcceptance(
          context: context,
          hostWithPort: ipAddress,
          useHttps: useHttps,
        );
        if (accepted && context.mounted) {
          try {
            return await _login(
              ipAddress,
              username,
              password,
              useHttps,
              context: context, // ignore: use_build_context_synchronously
              checkRedirect: false,
            );
          } on DioException catch (retryError, retryStack) {
            Logger.exception('Login retry after cert accept failed', retryError, retryStack);
          }
        }
      }

      if (isCertError) return null;
      rethrow;
    }
  }

  /// Parses the RUTOS /api/login JSON response and returns the token or null.
  String? _parseRutosToken(dynamic responseData) {
    try {
      final decoded = responseData is String
          ? jsonDecode(responseData)
          : responseData;
      if (decoded is Map && decoded['success'] == true) {
        return decoded['data']?['token'] as String?;
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) async {
    return await callWithContext(
      ipAddress,
      sysauth,
      useHttps,
      object: object,
      method: method,
      params: params,
      context: context,
    );
  }

  // Simplified call method for reviewer mode
  @override
  Future<dynamic> callSimple(
    String object,
    String method,
    Map<String, dynamic> params,
  ) async {
    // Use default values for ipAddress, sysauth, and useHttps
    // This is primarily for mock/testing scenarios
    return await call(
      'localhost', // Default IP address
      '', // Default sysauth (empty for mock scenarios)
      false, // Default to HTTP
      object: object,
      method: method,
      params: params,
    );
  }

  Future<dynamic> callWithContext(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) async {
    final String? path = _mapToRutosPath(object, method, params);
    if (path == null) {
      // Unsupported endpoint — return a graceful "access denied" marker
      // so optional callers silently skip it.
      Logger.debug('No RUTOS REST endpoint for $object.$method — skipping');
      return [6, 'Unsupported: $object.$method'];
    }

    final url = _buildUrl(ipAddress, useHttps, path);
    final client = _createHttpClient(useHttps, ipAddress, context: context);

    try {
      final response = await client.get(
        url.toString(),
        options: Options(
          headers: {
            'Authorization': 'Bearer $sysauth',
            'Accept-Encoding': 'identity',
          },
          responseType: ResponseType.bytes,
        ),
      );

      if (response.statusCode == 200) {
        final decoded = _decodeRestResponse(response.data as List<int>);
        if (decoded['success'] != true) {
          final errors = decoded['errors'];
          final code = (errors is List && errors.isNotEmpty)
              ? (errors.first as Map?)?.containsKey('code') == true
                  ? errors.first['code']
                  : null
              : null;
          if (code == 123) throw Exception('Session expired');
          final msg = (errors is List && errors.isNotEmpty)
              ? errors.first['error'] ?? 'API error'
              : 'API error';
          return [6, msg.toString()];
        }
        return _normalizeRutosResponse(object, method, decoded['data']);
      }
      throw Exception('Failed to call REST: HTTP ${response.statusCode}');
    } on DioException catch (e, stack) {
      Logger.exception('API call failed', e, stack);
      rethrow;
    }
  }

  /// Maps an (object, method) pair to the RUTOS REST API path.
  /// Returns null for unsupported/optional calls.
  String? _mapToRutosPath(String object, String method, Map<String, dynamic>? params) {
    switch ('$object.$method') {
      case 'system.board':
        return '/api/system/device/status';
      case 'system.info':
        return '/api/system/device/usage/status';
      case 'network.interface.dump':
      case 'luci-rpc.getNetworkDevices':
      case 'network.device.status':
        return '/api/interfaces/basic/status';
      case 'luci-rpc.getDHCPLeases':
      case 'dnsmasq.ipv4leases':
        return '/api/dhcp/leases/ipv4/status';
      case 'luci-rpc.getWirelessDevices':
      case 'network.wireless.status':
      case 'iwinfo.devices':
        return '/api/wireless/interfaces/status';
      case 'uci.get':
        // Only support the wireless config read
        if (params?['config'] == 'wireless') return '/api/wireless/interfaces/config';
        return null;
      default:
        return null;
    }
  }

  /// Normalises a RUTOS REST `data` payload to the `[0, data]` format that
  /// the rest of the app expects from the old ubus JSON-RPC calls.
  dynamic _normalizeRutosResponse(String object, String method, dynamic data) {
    switch ('$object.$method') {

      // system.board → return data.static (has hostname, model, kernel, release)
      case 'system.board':
        if (data is Map<String, dynamic>) {
          final staticData = (data['static'] as Map<String, dynamic>?) ?? data;
          return [0, staticData];
        }
        return [0, data];

      // system.info → convert RUTOS usage format to ubus system.info format
      case 'system.info':
        final d = (data as Map<String, dynamic>?) ?? {};
        final load = (d['load'] as Map<String, dynamic>?) ?? {};
        final memory = (d['memory'] as Map<String, dynamic>?) ?? {};
        final toBytes = (num mb) => (mb * 1024 * 1024).round();
        return [0, {
          'uptime': d['uptime_seconds'] ?? 0,
          'localtime': d['localtime'] ?? 0,
          'load': [
            ((load['min1'] as num? ?? 0) * 65536.0).round(),
            ((load['min5'] as num? ?? 0) * 65536.0).round(),
            ((load['min15'] as num? ?? 0) * 65536.0).round(),
          ],
          'memory': {
            'total': toBytes(memory['ram_total'] as num? ?? 0),
            'free':  toBytes(memory['ram_free']  as num? ?? 0),
            'shared': 0, 'buffered': 0,
            'available': toBytes(memory['ram_free'] as num? ?? 0),
            'cached': 0,
          },
        }];

      // network.interface dump → convert RUTOS array to {interface:[...]} format
      case 'network.interface.dump':
        final list = (data as List?) ?? [];
        final interfaces = list.whereType<Map<String, dynamic>>().map((iface) {
          final id = iface['id']?.toString() ?? iface['interface']?.toString() ?? '';
          final isWan = id == 'wan' || iface['area_type'] == 'wan';
          return <String, dynamic>{
            'interface': id,
            'up': iface['is_up'] ?? iface['enabled'] ?? false,
            'device': id,
            'l3_device': id,
            'proto': iface['proto'] ?? 'static',
            'uptime': iface['uptime'] ?? 0,
            'ipv4-address': iface['ipv4-address'] ?? [],
            'ipv6-address': iface['ip6addrs'] ?? [],
            // Synthetic default route so _extractWanData() detects the WAN iface
            'route': isWan ? [<String, dynamic>{'target': '0.0.0.0', 'mask': 0}] : [],
            'dns-server': iface['dns-server'] ?? [],
            'rx_bytes': iface['rx_bytes'] ?? 0,
            'tx_bytes': iface['tx_bytes'] ?? 0,
          };
        }).toList();
        return [0, <String, dynamic>{'interface': interfaces}];

      // getNetworkDevices / network.device.status → device-stats map for throughput
      case 'luci-rpc.getNetworkDevices':
      case 'network.device.status':
        final list2 = (data as List?) ?? [];
        final deviceMap = <String, dynamic>{};
        for (final iface in list2.whereType<Map<String, dynamic>>()) {
          final id = iface['id']?.toString() ?? iface['interface']?.toString() ?? '';
          if (id.isNotEmpty) {
            deviceMap[id] = <String, dynamic>{
              'rx_bytes': iface['rx_bytes'] ?? 0,
              'tx_bytes': iface['tx_bytes'] ?? 0,
              'up': iface['is_up'] ?? iface['enabled'] ?? false,
            };
          }
        }
        return [0, deviceMap];

      // getDHCPLeases / dnsmasq.ipv4leases → normalise to {dhcp_leases:[...]}
      case 'luci-rpc.getDHCPLeases':
      case 'dnsmasq.ipv4leases':
        final leaseList = (data as List?) ?? [];
        final normalized = leaseList.whereType<Map<String, dynamic>>()
            .map<Map<String, dynamic>>((l) => {
              'macaddr':   l['macaddr']  ?? l['mac']     ?? '',
              'ipaddr':    l['ipaddr']   ?? l['address'] ?? '',
              'hostname':  l['hostname'] ?? '',
              'leasetime': (l['expires'] as num?)?.toInt() ?? 0,
              'expires':   (l['expires'] as num?)?.toInt() ?? 0,
            }).toList();
        return [0, <String, dynamic>{'dhcp_leases': normalized}];

      // getWirelessDevices / wireless.status → format with interfaces[*].ifname
      case 'luci-rpc.getWirelessDevices':
      case 'network.wireless.status':
      case 'iwinfo.devices':
        // RUTOS returns array of AP objects; reshape to radio-keyed map
        final apList = (data as List?) ?? [];
        final radioMap = <String, dynamic>{};
        for (final ap in apList.whereType<Map<String, dynamic>>()) {
          final devicesList = ap['devices'];
          String? radioName;
          if (devicesList is List && devicesList.isNotEmpty) {
            final first = devicesList.first;
            if (first is Map<String, dynamic>) radioName = first['name']?.toString();
          }
          final ifname = ap['ifname'] as String?;
          final key = radioName ?? ifname ?? 'radio0';
          radioMap[key] = <String, dynamic>{
            'up': ap['up'] ?? true,
            'interfaces': [<String, dynamic>{
              'ifname': ifname ?? '',
              'config': <String, dynamic>{'ssid': ap['ssid'] ?? ''},
            }],
            // Store clients for fetchAllAssociatedWirelessMacsWithContext
            '_clients': ap['clients'] ?? [],
          };
        }
        return [0, radioMap];

      // uci.get wireless → pass through the raw config
      case 'uci.get':
        return [0, data];

      default:
        return [0, data];
    }
  }

  /// Decodes a RUTOS REST API response body, transparently decompressing gzip
  /// (RUTOS uhttpd may send Content-Encoding: gzip regardless of Accept-Encoding).
  Map<String, dynamic> _decodeRestResponse(List<int> bytes) {
    List<int> body = bytes;
    if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
      body = GZipCodec().decode(bytes);
    }
    return jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
  }

  // Keep _decodeRpcResponse as an alias for backward compat
  Map<String, dynamic> _decodeRpcResponse(List<int> bytes) => _decodeRestResponse(bytes);

  @override
  Future<bool> reboot(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    return await rebootWithContext(
      ipAddress,
      sysauth,
      useHttps,
      context: context,
    );
  }

  Future<bool> rebootWithContext(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    try {
      final url = _buildUrl(ipAddress, useHttps, '/api/system/actions/reboot');
      final client = _createHttpClient(useHttps, ipAddress, context: context);
      final response = await client.post(
        url.toString(),
        options: Options(headers: {'Authorization': 'Bearer $sysauth'}),
      );
      if (response.statusCode == 200) {
        Logger.info('Router reboot initiated successfully');
        return true;
      }
      Logger.warning('Reboot returned HTTP ${response.statusCode}');
      return false;
    } catch (e, stack) {
      Logger.exception('Router reboot failed', e, stack);
      return false;
    }
  }

  @override
  Future<Map<String, Set<String>>> fetchAssociatedStations() async {
    // This method is mainly used by the mock service
    // For real implementation, individual interface queries via fetchAssociatedStationsWithContext should be used
    // The app_state.dart should call fetchAllAssociatedWirelessMacsWithContext instead
    throw UnimplementedError(
      'Use fetchAllAssociatedWirelessMacsWithContext for real implementation',
    );
  }

  /// Fetches all associated wireless MAC addresses using RUTOS /api/wireless/interfaces/status.
  /// The endpoint returns clients[*].macaddr directly — no separate assoclist call needed.
  @override
  Future<Map<String, Set<String>>> fetchAllAssociatedWirelessMacsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async {
    try {
      final url = _buildUrl(ipAddress, useHttps, '/api/wireless/interfaces/status');
      final client = _createHttpClient(useHttps, ipAddress, context: context);
      final response = await client.get(
        url.toString(),
        options: Options(
          headers: {'Authorization': 'Bearer $sysauth', 'Accept-Encoding': 'identity'},
          responseType: ResponseType.bytes,
        ),
      );
      if (response.statusCode != 200) return {};
      final decoded = _decodeRestResponse(response.data as List<int>);
      if (decoded['success'] != true) return {};
      final apList = (decoded['data'] as List?) ?? [];
      final result = <String, Set<String>>{};
      for (final ap in apList.whereType<Map<String, dynamic>>()) {
        final ifname = ap['ifname'] as String? ?? 'wlan0';
        final clients = (ap['clients'] as List?) ?? [];
        final macs = clients
            .whereType<Map<String, dynamic>>()
            .map((c) => c['macaddr']?.toString() ?? '')
            .where((m) => m.isNotEmpty)
            .toSet();
        if (macs.isNotEmpty) result[ifname] = macs;
      }
      return result;
    } catch (e, stack) {
      Logger.exception('Failed to fetch associated wireless MACs', e, stack);
      return {};
    }
  }

  /// Fetches associated stations (wireless clients) for a given wireless interface (e.g., wlan0)
  @override
  Future<List<String>> fetchAssociatedStationsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
    BuildContext? context,
  }) async {
    try {
      final result = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'iwinfo',
        method: 'assoclist',
        params: {'device': interface},
        context: context,
      );
      // Handle LuCI RPC format: [status, data]
      if (result is List && result.length > 1 && result[0] == 0) {
        final data = result[1];
        if (data is Map && data['results'] is List) {
          final resultsList = data['results'] as List;
          return resultsList
              .map(
                (entry) => (entry as Map<String, dynamic>)['mac']?.toString(),
              )
              .where((mac) => mac != null)
              .cast<String>()
              .toList();
        }
      }
      return [];
    } catch (e, stack) {
      Logger.exception('Failed to fetch associated stations', e, stack);
      return [];
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchWireGuardPeers({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
    BuildContext? context,
  }) async {
    return await fetchWireGuardPeersWithContext(
      ipAddress: ipAddress,
      sysauth: sysauth,
      useHttps: useHttps,
      interface: interface,
      context: context,
    );
  }

  /// Fetches WireGuard peer information for a given interface
  /// If interface is empty, returns data for all WireGuard interfaces
  Future<Map<String, dynamic>?> fetchWireGuardPeersWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
    BuildContext? context,
  }) async {
    try {
      // Use the correct luci.wireguard.getWgInstances method
      final result = await callWithContext(
        ipAddress,
        sysauth,
        useHttps,
        object: 'luci.wireguard',
        method: 'getWgInstances',
        params: {},
        context: context,
      );

      // Handle LuCI RPC format: [status, data]
      if (result is List && result.length > 1 && result[0] == 0) {
        final data = result[1] as Map<String, dynamic>?;
        if (data != null) {
          return _parseWireGuardFromInstances(data, interface);
        }
      }

      return null;
    } catch (e, stack) {
      Logger.exception('Failed to fetch WireGuard peers', e, stack);
      return null;
    }
  }

  Map<String, dynamic>? _parseWireGuardFromInstances(
    Map<String, dynamic> data,
    String targetInterface,
  ) {
    final wireguardData = <String, dynamic>{};

    data.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        // Look for peers in the interface data
        final peers = <String, dynamic>{};

        // The structure might have peers in different formats
        if (value['peers'] is List) {
          final peersList = value['peers'] as List;
          for (final peer in peersList) {
            if (peer is Map<String, dynamic>) {
              final publicKey = peer['public_key'] as String?;
              if (publicKey != null) {
                peers[publicKey] = {
                  'public_key': publicKey,
                  'endpoint': peer['endpoint'] ?? 'N/A',
                  'last_handshake':
                      int.tryParse(
                        peer['latest_handshake']?.toString() ?? '0',
                      ) ??
                      0,
                };
              }
            }
          }
        } else if (value['peers'] is Map<String, dynamic>) {
          final peersMap = value['peers'] as Map<String, dynamic>;
          peersMap.forEach((peerKey, peerData) {
            if (peerData is Map<String, dynamic>) {
              peers[peerKey] = {
                'public_key': peerKey,
                'endpoint': peerData['endpoint'] ?? 'N/A',
                'last_handshake':
                    int.tryParse(
                      peerData['latest_handshake']?.toString() ?? '0',
                    ) ??
                    0,
              };
            }
          });
        }

        if (peers.isNotEmpty) {
          wireguardData[key] = {'interface': key, 'peers': peers};
        }
      }
    });

    if (targetInterface.isEmpty) {
      return wireguardData;
    } else {
      return wireguardData[targetInterface];
    }
  }

  @override
  Future<dynamic> uciSet(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String section,
    required Map<String, String> values,
    BuildContext? context,
  }) async {
    return await callWithContext(
      ipAddress,
      sysauth,
      useHttps,
      object: 'uci',
      method: 'set',
      params: {'config': config, 'section': section, 'values': values},
      context: context,
    );
  }

  @override
  Future<dynamic> uciCommit(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  }) async {
    return await callWithContext(
      ipAddress,
      sysauth,
      useHttps,
      object: 'uci',
      method: 'commit',
      params: {'config': config},
      context: context,
    );
  }

  @override
  Future<dynamic> systemExec(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    BuildContext? context,
  }) async {
    return await callWithContext(
      ipAddress,
      sysauth,
      useHttps,
      object: 'system',
      method: 'exec',
      params: {'command': command},
      context: context,
    );
  }

  /// Fetches DHCP leases from RUTOS REST API (/api/dhcp/leases/ipv4/status)
  /// and normalises to the {dhcp_leases:[...]} format expected by the rest of the app.
  Future<dynamic> _callRutosDhcpLeases(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    // Delegate to callWithContext which maps to /api/dhcp/leases/ipv4/status
    return await callWithContext(
      ipAddress, sysauth, useHttps,
      object: 'luci-rpc', method: 'getDHCPLeases', params: {},
      context: context,
    );
  }
}
