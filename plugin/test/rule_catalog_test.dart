import 'dart:io';

import 'package:neon_lints/src/rule_catalog.dart';
import 'package:test/test.dart';

void main() {
  test('rule_catalog.json matches the rule classes (dart run tool/generate_rule_catalog.dart)', () {
    expect(File('rule_catalog.json').readAsStringSync(), ruleCatalogJson());
  });

  test('every rule explains itself: a description, a message and what to do instead', () {
    for (final rule in ruleCatalog()) {
      expect(rule.description, isNotEmpty, reason: rule.name);
      expect(rule.message, isNotEmpty, reason: rule.name);
      expect(rule.correction, isNotEmpty, reason: rule.name);
    }
  });
}
