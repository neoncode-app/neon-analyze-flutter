import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/error/error.dart';
// The diagnostic codes are not exported from a public library.
// ignore: implementation_imports
import 'package:analyzer/src/diagnostic/diagnostic.dart' as diag;
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';

import 'expect.dart';
import 'stub_packages.dart';

/// Base of the architecture-rule tests: Flutter, bloc, provider,
/// bloc_presentation and go_router stubs plus the app's BaseCubit, AlertCubit
/// and Utils.
abstract class BlocRuleTest extends AnalysisRuleTest {
  AnalysisRule get ruleUnderTest;

  // The shared imports are not all used by every snippet.
  @override
  List<DiagnosticCode> get ignoredDiagnosticCodes => [...super.ignoredDiagnosticCodes, diag.unusedImport];

  @override
  void setUp() {
    rule = ruleUnderTest;
    addStubPackages(this);
    addBlocPackages(this);
    addAppBlocClasses(this);
    addPresentationPackages(this);
    super.setUp();
  }

  /// Writes [source] at `lib/<relativePath>` and checks the [flagged] texts.
  Future<void> expectIn(
    String relativePath,
    String source,
    List<String> flagged, {
    List<Pattern> message = const [],
    String? after,
  }) {
    final path = '$testPackageLibPath/$relativePath';
    newFile(path, source);
    return assertDiagnosticsInFile(path, lintsAt(this, source, flagged, messageContainsAll: message, after: after));
  }
}
