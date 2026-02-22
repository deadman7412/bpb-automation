import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bpb_automation/services/config_generator_service.dart';
import 'package:bpb_automation/models/xray_config.dart';
import 'package:bpb_automation/models/outbound.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConfigGeneratorService', () {
    late ConfigGeneratorService service;

    setUp(() {
      service = ConfigGeneratorService.instance;
    });

    group('generateConfigsWithIPs', () {
      test('generates correct number of configs for valid IPs', () async {
        // Create a valid template config
        final template = XrayConfig(
          outbounds: [
            Outbound.fromJson({
              'tag': 'proxy',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': '1.1.1.1',
                    'port': 443,
                    'users': [
                      {'id': 'test-uuid', 'encryption': 'none'},
                    ],
                  },
                ],
              },
              'streamSettings': {'network': 'tcp', 'security': 'tls'},
            }),
          ],
          inbounds: [],
          log: {},
          remarks: 'Test Config',
        );

        final workingIPs = ['1.2.3.4', '5.6.7.8', '9.10.11.12'];

        final configs = await service.generateConfigsWithIPs(
          template: template,
          workingIPs: workingIPs,
        );

        expect(configs.length, equals(3));
      });

      test('updates remarks with IP and index', () async {
        final template = XrayConfig(
          outbounds: [
            Outbound.fromJson({
              'tag': 'proxy',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': '1.1.1.1',
                    'port': 443,
                    'users': [
                      {'id': 'test-uuid', 'encryption': 'none'},
                    ],
                  },
                ],
              },
              'streamSettings': {'network': 'tcp', 'security': 'tls'},
            }),
          ],
          inbounds: [],
          log: {},
          remarks: 'BPB Config',
        );

        final workingIPs = ['1.2.3.4', '5.6.7.8'];

        final configs = await service.generateConfigsWithIPs(
          template: template,
          workingIPs: workingIPs,
        );

        expect(configs[0].remarks, contains('1.2.3.4'));
        expect(configs[0].remarks, contains('1/2'));
        expect(configs[1].remarks, contains('5.6.7.8'));
        expect(configs[1].remarks, contains('2/2'));
      });

      test('replaces IP addresses correctly', () async {
        final template = XrayConfig(
          outbounds: [
            Outbound.fromJson({
              'tag': 'proxy',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': '1.1.1.1',
                    'port': 443,
                    'users': [
                      {'id': 'test-uuid', 'encryption': 'none'},
                    ],
                  },
                ],
              },
              'streamSettings': {'network': 'tcp', 'security': 'tls'},
            }),
          ],
          inbounds: [],
          log: {},
        );

        final workingIPs = ['9.9.9.9'];

        final configs = await service.generateConfigsWithIPs(
          template: template,
          workingIPs: workingIPs,
        );

        expect(configs.length, equals(1));
        expect(configs[0].getServerAddress(), equals('9.9.9.9'));
      });

      test('preserves policy/stats/api sections', () async {
        final template = XrayConfig(
          outbounds: [
            Outbound.fromJson({
              'tag': 'proxy',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': '1.1.1.1',
                    'port': 443,
                    'users': [
                      {'id': 'test-uuid', 'encryption': 'none'},
                    ],
                  },
                ],
              },
            }),
          ],
          inbounds: [],
          log: {},
          policy: {
            'levels': {
              '0': {'handshake': 4},
            },
          },
          stats: {'enabled': true},
          api: {'services': ['StatsService']},
        );

        final configs = await service.generateConfigsWithIPs(
          template: template,
          workingIPs: ['9.9.9.9'],
        );

        expect(configs.length, equals(1));
        expect(configs[0].policy, isNotNull);
        expect(configs[0].stats, isNotNull);
        expect(configs[0].api, isNotNull);
      });

      test('returns empty list for empty IPs', () async {
        final template = XrayConfig(
          outbounds: [
            Outbound.fromJson({
              'tag': 'proxy',
              'protocol': 'vless',
              'settings': {
                'vnext': [
                  {
                    'address': '1.1.1.1',
                    'port': 443,
                    'users': [
                      {'id': 'test-uuid', 'encryption': 'none'},
                    ],
                  },
                ],
              },
            }),
          ],
          inbounds: [],
          log: {},
        );

        final configs = await service.generateConfigsWithIPs(
          template: template,
          workingIPs: [],
        );

        expect(configs, isEmpty);
      });

      test('returns empty list for invalid template', () async {
        // Create invalid config (no outbounds)
        final template = XrayConfig(outbounds: [], inbounds: [], log: {});

        final configs = await service.generateConfigsWithIPs(
          template: template,
          workingIPs: ['1.2.3.4'],
        );

        expect(configs, isEmpty);
      });
    });

    group('exportConfigsAsJSON', () {
      test('exports configs as valid JSON array', () {
        final configs = [
          XrayConfig(
            outbounds: [
              Outbound.fromJson({
                'tag': 'proxy',
                'protocol': 'vless',
                'settings': {
                  'vnext': [
                    {
                      'address': '1.2.3.4',
                      'port': 443,
                      'users': [
                        {'id': 'test-uuid', 'encryption': 'none'},
                      ],
                    },
                  ],
                },
              }),
            ],
            inbounds: [],
            log: {},
            remarks: 'Test 1',
          ),
          XrayConfig(
            outbounds: [
              Outbound.fromJson({
                'tag': 'proxy',
                'protocol': 'vless',
                'settings': {
                  'vnext': [
                    {
                      'address': '5.6.7.8',
                      'port': 443,
                      'users': [
                        {'id': 'test-uuid', 'encryption': 'none'},
                      ],
                    },
                  ],
                },
              }),
            ],
            inbounds: [],
            log: {},
            remarks: 'Test 2',
          ),
        ];

        final jsonString = service.exportConfigsAsJSON(configs);

        expect(jsonString, isNotEmpty);
        expect(jsonString, startsWith('['));
        expect(jsonString, endsWith(']'));
        expect(jsonString, contains('Test 1'));
        expect(jsonString, contains('Test 2'));
        expect(jsonString, contains('1.2.3.4'));
        expect(jsonString, contains('5.6.7.8'));
      });

      test('returns empty array for empty configs', () {
        final jsonString = service.exportConfigsAsJSON([]);
        expect(jsonString, equals('[]'));
      });

      test('formats JSON with indentation', () {
        final configs = [
          XrayConfig(
            outbounds: [
              Outbound.fromJson({
                'tag': 'proxy',
                'protocol': 'vless',
                'settings': {
                  'vnext': [
                    {'address': '1.2.3.4', 'port': 443},
                  ],
                },
              }),
            ],
            inbounds: [],
            log: {},
          ),
        ];

        final jsonString = service.exportConfigsAsJSON(configs);

        // Check for indentation (pretty print)
        expect(jsonString, contains('  '));
        expect(jsonString, contains('\n'));
      });
    });

    group('saveConfigsToFile', () {
      test('saves configs to file on non-web platforms', () async {
        final configs = [
          XrayConfig(
            outbounds: [
              Outbound.fromJson({
                'tag': 'proxy',
                'protocol': 'vless',
                'settings': {
                  'vnext': [
                    {'address': '1.2.3.4', 'port': 443},
                  ],
                },
              }),
            ],
            inbounds: [],
            log: {},
            remarks: 'Test Config',
          ),
        ];

        final filePath = await service.saveConfigsToFile(configs);

        if (filePath != null) {
          // Verify file exists
          final file = File(filePath);
          expect(file.existsSync(), isTrue);

          // Verify content
          final content = await file.readAsString();
          expect(content, contains('Test Config'));
          expect(content, contains('1.2.3.4'));

          // Cleanup
          await file.delete();
        }
      });

      test('uses custom filename when provided', () async {
        final configs = [
          XrayConfig(
            outbounds: [
              Outbound.fromJson({
                'tag': 'proxy',
                'protocol': 'vless',
                'settings': {
                  'vnext': [
                    {'address': '1.2.3.4', 'port': 443},
                  ],
                },
              }),
            ],
            inbounds: [],
            log: {},
          ),
        ];

        final customFilename = 'test_custom_configs.json';
        final filePath = await service.saveConfigsToFile(
          configs,
          filename: customFilename,
        );

        if (filePath != null) {
          expect(filePath, contains(customFilename));

          // Cleanup
          final file = File(filePath);
          if (file.existsSync()) {
            await file.delete();
          }
        }
      });
    });

    group('getConfigsSummary', () {
      test('returns correct summary for single config', () {
        final configs = [
          XrayConfig(
            outbounds: [
              Outbound.fromJson({
                'tag': 'proxy',
                'protocol': 'vless',
                'settings': {
                  'vnext': [
                    {'address': '1.2.3.4', 'port': 443},
                  ],
                },
                'streamSettings': {'security': 'tls'},
              }),
            ],
            inbounds: [],
            log: {},
          ),
        ];

        final summary = service.getConfigsSummary(configs);

        expect(summary, contains('1 config'));
        expect(summary, contains('vless'));
        expect(summary.contains('configs'), isFalse); // Singular form
      });

      test('returns correct summary for multiple configs', () {
        final configs = [
          XrayConfig(
            outbounds: [
              Outbound.fromJson({
                'tag': 'proxy',
                'protocol': 'vmess',
                'settings': {
                  'vnext': [
                    {'address': '1.2.3.4', 'port': 443},
                  ],
                },
              }),
            ],
            inbounds: [],
            log: {},
          ),
          XrayConfig(
            outbounds: [
              Outbound.fromJson({
                'tag': 'proxy',
                'protocol': 'vmess',
                'settings': {
                  'vnext': [
                    {'address': '5.6.7.8', 'port': 443},
                  ],
                },
              }),
            ],
            inbounds: [],
            log: {},
          ),
        ];

        final summary = service.getConfigsSummary(configs);

        expect(summary, contains('2 configs'));
        expect(summary, contains('vmess'));
      });

      test('returns message for empty configs', () {
        final summary = service.getConfigsSummary([]);
        expect(summary, equals('No configs generated'));
      });

      test('includes security info in summary', () {
        final configs = [
          XrayConfig(
            outbounds: [
              Outbound.fromJson({
                'tag': 'proxy',
                'protocol': 'vless',
                'settings': {
                  'vnext': [
                    {'address': '1.2.3.4', 'port': 443},
                  ],
                },
                'streamSettings': {'security': 'tls'},
              }),
            ],
            inbounds: [],
            log: {},
          ),
        ];

        final summary = service.getConfigsSummary(configs);

        expect(summary, contains('Security:'));
        expect(summary, contains('TLS/Reality'));
      });
    });

    group('singleton pattern', () {
      test('returns same instance', () {
        final instance1 = ConfigGeneratorService.instance;
        final instance2 = ConfigGeneratorService.instance;

        expect(identical(instance1, instance2), isTrue);
      });
    });
  });
}
