// Writes rule_catalog.json: every neon_lints rule with its description,
// message and correction, read from the rule classes themselves. neon-check
// reads the catalog (the rule brief for the AI, `explain`) without loading
// the analyzer; test/rule_catalog_test.dart fails when it is stale.
//
//   cd neon-analyze-flutter/plugin && dart run tool/generate_rule_catalog.dart
import 'dart:io';

import 'package:neon_lints/src/rule_catalog.dart';

void main() {
  File('rule_catalog.json').writeAsStringSync(ruleCatalogJson());
  stdout.writeln('rule_catalog.json: ${ruleCatalog().length} rules');
}
