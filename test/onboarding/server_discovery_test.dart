// Copyright (c) 2026 Contributors to the Suwayomi project
//
// Unit tests for LAN server discovery (the "Search my network" sweep).

import 'package:flutter_test/flutter_test.dart';
import 'package:kuchie/src/features/onboarding/data/server_discovery.dart';

/// A [ServerConfirmer] that confirms exactly the URLs in [known], tagging each
/// with a name/version so the caller can tell them apart.
ServerConfirmer _confirmer(Map<String, DiscoveredServer> known) =>
    (url) async => known[url];

void main() {
  test('sweeps the subnet, finds 4568 and rejects non-Suwayomi', () async {
    final hosts = subnetHosts('192.168.1.50');
    expect(hosts, contains('192.168.1.1'));
    expect(hosts, contains('192.168.1.254'));
    expect(hosts.first, '192.168.1.50'); // ip probed first
    expect(hosts.where((h) => h == '192.168.1.50').length, 1); // de-duped
    expect(hosts.length, 254);

    final found = await discoverServersOnLan(
      wifiIp: () async => '192.168.1.50',
      ping: (host, port) async => host == '192.168.1.7' && port == 4568,
      confirm: _confirmer({
        'http://192.168.1.7:4568': const DiscoveredServer(
          url: 'http://192.168.1.7:4568',
          name: 'Suwayomi-Server',
          version: '2.3.2162',
        ),
      }),
    );
    expect(found, hasLength(1));
    expect(found.single.url, 'http://192.168.1.7:4568');
    expect(found.single.name, 'Suwayomi-Server');
    expect(found.single.version, '2.3.2162');
    expect(found.single.address, '192.168.1.7:4568');

    // An open port that is not Suwayomi is not reported.
    final notSuwayomi = await discoverServersOnLan(
      wifiIp: () async => '192.168.1.50',
      ping: (host, port) async => host == '192.168.1.9' && port == 4567,
      confirm: _confirmer(const {}),
    );
    expect(notSuwayomi, isEmpty);
  });

  test('scans the Wi-Fi subnet, not cellular or VPN interfaces', () {
    expect(
      pickLanAddress([
        ('pdp_ip0', '10.64.12.7'),
        ('utun3', '10.8.0.2'),
        ('en0', '192.168.1.23'),
      ]),
      '192.168.1.23',
    );
    expect(pickLanAddress([('pdp_ip0', '10.64.12.7')]), isNull);
    expect(
      pickLanAddress([('bridge100', '192.168.2.1'), ('en1', '10.0.0.4')]),
      '10.0.0.4',
    );
  });

  test('treats private, .local and link-local hosts as local network', () {
    expect(isLocalNetworkHost('192.168.1.10'), isTrue);
    expect(isLocalNetworkHost('10.0.0.5'), isTrue);
    expect(isLocalNetworkHost('172.20.1.1'), isTrue);
    expect(isLocalNetworkHost('suwayomi.local'), isTrue);
    expect(isLocalNetworkHost('169.254.3.4'), isTrue);
    expect(isLocalNetworkHost('100.101.102.103'), isFalse);
    expect(isLocalNetworkHost('example.com'), isFalse);
  });
}
