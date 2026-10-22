import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/error/error.dart';
// The diagnostic codes are not exported from a public library.
// ignore: implementation_imports
import 'package:analyzer/src/diagnostic/diagnostic.dart' as diag;
import 'package:neon_lints/src/shared_functions.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';
import 'support/stub_packages.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(SharedFunctionsTest);
  });
}

const _cubit = 'bloc/vernak/cards/cards_cubit.dart';

@reflectiveTest
class SharedFunctionsTest extends BlocRuleTest {
  @override
  AnalysisRule get ruleUnderTest => SharedFunctions();

  // The mock SDK's String has no trim().
  @override
  List<DiagnosticCode> get ignoredDiagnosticCodes => [...super.ignoredDiagnosticCodes, diag.undefinedMethod];

  @override
  void setUp() {
    super.setUp();
    patchMockSdk(this);
    newFile('$testPackageLibPath/bloc/global/close_dialog.dart', '''
class CloseDialog {}

void emitPresentation(Object event) {}
''');
  }

  Future<void> test_set_copies_are_flagged() => expectIn(
        _cubit,
        '''
Set<String> remove(Set<String> ids, String id) => {...ids}..remove(id);

Set<String> add(Set<String> ids, String id) => {...ids, id};

Set<String> copy(Set<String> ids) => {...ids};
''',
        ['{...ids}', '{...ids, id}'],
      );

  Future<void> test_replace_and_remove_by_id_are_flagged() => expectIn(
        _cubit,
        '''
class Card {
  const Card(this.id);
  final String id;
}

List<Card> replace(List<Card> cards, Card card) => cards.map((c) => c.id == card.id ? card : c).toList();

List<Card> rebuild(List<Card> cards, Card card) => [for (final c in cards) if (c.id == card.id) card else c];

List<Card> remove(List<Card> cards, String id) => cards.where((c) => c.id != id).toList();

List<Card> keep(List<Card> cards, String id) => cards.where((c) => c.id == id).toList();
''',
        ['map', 'for (final c in cards) if (c.id == card.id) card else c', 'where'],
      );

  Future<void> test_hand_made_query_matching_is_flagged() => expectIn(
        _cubit,
        '''
bool matches(String name, String query) {
  final q = query.trim().toLowerCase();
  return name.toLowerCase().contains(q);
}

String normalise(String query) => query.trim().toLowerCase();
''',
        ['toLowerCase'],
      );

  Future<void> test_close_dialog_before_return_is_flagged() => expectIn(
        _cubit,
        '''
import 'package:test/bloc/global/close_dialog.dart';

Future<bool> save(Future<bool> Function() work) {
  emitPresentation(CloseDialog());
  return work();
}

void close() {
  emitPresentation(CloseDialog());
}
''',
        ['emitPresentation(CloseDialog());'],
      );

  Future<void> test_upload_endpoint_is_flagged() => expectIn(
        _cubit,
        "const endpoint = '/api/uploads';\n",
        ["'/api/uploads'"],
      );

  Future<void> test_outside_ui_and_cubits_is_clean() => expectIn(
        'utils/helpers/image_upload.dart',
        '''
const endpoint = '/api/uploads';

Set<String> remove(Set<String> ids, String id) => {...ids}..remove(id);
''',
        [],
      );

  Future<void> test_base_cubit_owns_the_dialog_helpers() => expectIn(
        'bloc/global/base/base_cubit.dart',
        '''
import 'package:test/bloc/global/close_dialog.dart';

Future<T> closeDialogThen<T>(Future<T> Function() work) {
  emitPresentation(CloseDialog());
  return work();
}
''',
        [],
      );

  Future<void> test_a_base_cubit_without_an_owner_folder_owns_them_too() => expectIn(
        'bloc/base/base_cubit.dart',
        '''
import 'package:test/bloc/global/close_dialog.dart';

Future<T> closeDialogThen<T>(Future<T> Function() work) {
  emitPresentation(CloseDialog());
  return work();
}
''',
        [],
      );
}
