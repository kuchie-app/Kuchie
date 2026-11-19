// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';

import 'server_resolver.dart';

// 4567 is Suwayomi's default; 4568-4570 cover alternate local ports.
const List<int> kSuwayomiScanPorts = [4567, 4568, 4569, 4570];

class DiscoveredServer {
  const DiscoveredServer({required this.url, this.name, this.version});

  /// Discovered URLs use `http://<ip>:<port>`.
  final String url;

  final String? name;

  final String? version;

  String get host => Uri.parse(url).host;

  int get port => Uri.parse(url).port;

  String get address => '$host:$port';
}

/// Confirms Suwayomi via aboutServer; returns null for other services.
typedef ServerConfirmer = Future<DiscoveredServer?> Function(String url);

/// Returns /24 hosts .1 through .254 plus [ip], in order without duplicates.
List<String> subnetHosts(String ip) {
  final dot = ip.lastIndexOf('.');
  if (dot < 0) return [ip];
  final subnet = ip.substring(0, dot);
  return <String>{ip, for (var i = 1; i < 255; i++) '$subnet.$i'}.toList();
}

/// Confirms TCP responders with at most 8 confirmations in flight; returns IP/port-sorted servers.
/// Returns empty without a Wi-Fi IP; batches of 128 TCP probes stay below mobile socket limits.
Future<List<DiscoveredServer>> discoverServersOnLan({
  Future<String?> Function()? wifiIp,
  Future<bool> Function(String host, int port)? ping,
  ServerConfirmer? confirm,
  List<int> ports = kSuwayomiScanPorts,
  int batchSize = 128,
}) async {
  final ip = await (wifiIp ?? localLanIp)();
  if (ip == null || ip.isEmpty) return const [];

  final doPing = ping ?? _ping;
  final targets = <(String, int)>[
    for (final host in subnetHosts(ip))
      for (final port in ports) (host, port),
  ];

  final open = <String>[];
  for (var start = 0; start < targets.length; start += batchSize) {
    final end = (start + batchSize) < targets.length
        ? start + batchSize
        : targets.length;
    final batch = targets.sublist(start, end);
    final results = await Future.wait(
      batch.map(
        (t) async =>
            (await doPing(t.$1, t.$2)) ? 'http://${t.$1}:${t.$2}' : null,
      ),
    );
    open.addAll(results.whereType<String>());
  }
  if (open.isEmpty) return const [];

  final doConfirm = confirm ?? _confirmSuwayomi;
  final found = (await _mapConcurrent(
    open,
    8,
    doConfirm,
  )).whereType<DiscoveredServer>().toList();
  found.sort(_byHostThenPort);
  return found;
}

/// Runs at most [limit] calls concurrently and preserves input order.
Future<List<T>> _mapConcurrent<A, T>(
  List<A> items,
  int limit,
  Future<T> Function(A item) run,
) async {
  final results = List<T?>.filled(items.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < items.length) {
      final i = next++;
      results[i] = await run(items[i]);
    }
  }

  await Future.wait([
    for (var i = 0; i < limit && i < items.length; i++) worker(),
  ]);
  return results.cast<T>();
}

Future<DiscoveredServer?> _confirmSuwayomi(String url) async {
  final client = http.Client();
  try {
    final result = await probeServer(url, client: client);
    if (!result.confirmed) return null;
    return DiscoveredServer(
      url: url,
      name: result.serverName,
      version: result.serverVersion,
    );
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

// Sort IPv4 hosts numerically so .2 precedes .10; use string order otherwise.
int _byHostThenPort(DiscoveredServer a, DiscoveredServer b) {
  final ao = a.host.split('.');
  final bo = b.host.split('.');
  if (ao.length == 4 && bo.length == 4) {
    for (var i = 0; i < 4; i++) {
      final c = (int.tryParse(ao[i]) ?? 0).compareTo(int.tryParse(bo[i]) ?? 0);
      if (c != 0) return c;
    }
  } else {
    final c = a.host.compareTo(b.host);
    if (c != 0) return c;
  }
  return a.port.compareTo(b.port);
}

Future<bool> _ping(String host, int port) async {
  try {
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(milliseconds: 1000),
    );
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

// Interface lookup needs no runtime permission; Wi-Fi plugin fallback may require location access.
Future<String?> localLanIp() async {
  try {
    final ifaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    if (pickLanAddress([
          for (final iface in ifaces)
            for (final addr in iface.addresses) (iface.name, addr.address),
        ])
        case final ip?) {
      return ip;
    }
  } catch (_) {}
  try {
    return await NetworkInfo().getWifiIP();
  } catch (_) {
    return null;
  }
}

/// The private IPv4 address of the Wi-Fi or Ethernet interface, from
/// (interface name, address) pairs. iPhones also list cellular (`pdp_ip`,
/// often 10.x behind carrier NAT) and VPN (`utun`, `ipsec`) interfaces, and
/// scanning their subnet never finds a server on the home network.
String? pickLanAddress(List<(String, String)> addresses) {
  const skipped = ['pdp_ip', 'utun', 'ipsec', 'ppp', 'awdl', 'llw', 'bridge'];
  int rank(String name) => name.startsWith('en') || name.startsWith('eth')
      ? 0
      : name.startsWith('wlan')
      ? 0
      : 1;
  final candidates = [
    for (final (name, ip) in addresses)
      if (_isPrivateV4(ip) && !skipped.any(name.startsWith)) (name, ip),
  ]..sort((a, b) => rank(a.$1).compareTo(rank(b.$1)));
  return candidates.firstOrNull?.$2;
}

/// Whether [host] is on the local network, where iOS asks for Local
/// Network permission before an app may connect.
bool isLocalNetworkHost(String host) {
  final lower = host.toLowerCase();
  if (lower.endsWith('.local')) return true;
  if (_isPrivateV4(host)) return true;
  final parts = host.split('.');
  return parts.length == 4 && parts[0] == '169' && parts[1] == '254';
}

// RFC 1918 ranges: 10/8, 172.16/12, 192.168/16.
bool _isPrivateV4(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return false;
  final a = int.tryParse(parts[0]);
  final b = int.tryParse(parts[1]);
  if (a == null || b == null) return false;
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
}
