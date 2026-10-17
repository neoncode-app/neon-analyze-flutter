import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/error/error.dart';
// The diagnostic codes are not exported from a public library.
// ignore: implementation_imports
import 'package:analyzer/src/diagnostic/diagnostic.dart' as diag;
import 'package:neon_lints/src/model_layout_rules.dart';
import 'package:neon_lints/src/model_serialization_rules.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';
import 'support/stub_packages.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ModelUsesJsonSerializableTest);
    defineReflectiveTests(NoDynamicInModelsTest);
    defineReflectiveTests(JsonConverterIsNoModelTest);
    defineReflectiveTests(JsonConverterInModelTest);
  });
}

/// The model rules with the json_annotation stubs. The generated part does
/// not exist in the tests, so its functions are unresolved.
abstract class _SerializationTest extends BlocRuleTest {
  @override
  List<DiagnosticCode> get ignoredDiagnosticCodes => [
        ...super.ignoredDiagnosticCodes,
        diag.uriHasNotBeenGenerated,
        diag.undefinedFunction,
        diag.undefinedMethod,
      ];

  @override
  void setUp() {
    addJsonPackages(this);
    super.setUp();
  }
}

const _json = "import 'package:json_annotation/json_annotation.dart';\n\n";

@reflectiveTest
class ModelUsesJsonSerializableTest extends _SerializationTest {
  @override
  AnalysisRule get ruleUnderTest => ModelUsesJsonSerializable();

  Future<void> test_generated_model_is_clean() => expectIn(
        'model/user.dart',
        '''
${_json}part 'user.g.dart';

@JsonSerializable()
class User {
  const User(this.name);
  factory User.fromJson(Map<String, dynamic> json) => _\$UserFromJson(json);
  final String name;
  Map<String, dynamic> toJson() => _\$UserToJson(this);
  Map<String, dynamic> toJsonWithoutToken() => toJson()..remove('token');
}

@JsonSerializable(createToJson: false)
class ApiError {
  const ApiError(this.code);
  factory ApiError.fromJson(Map<String, dynamic> json) {
    return _\$ApiErrorFromJson(json);
  }
  final String code;
}
''',
        [],
      );

  Future<void> test_hand_written_model_is_flagged() => expectIn(
        'model/vernak/vernak_coupon.dart',
        '''
${_json}class VernakCoupon {
  const VernakCoupon(this.name);
  factory VernakCoupon.fromJson(Map<String, dynamic> json) => VernakCoupon(json['name'] as String);
  final String name;
  Map<String, dynamic> toJson() => {'name': name};
}

@JsonSerializable()
class Invoice {
  const Invoice(this.id);
  static Invoice fromJson(Map<String, dynamic> json) => Invoice(json['id'] as String);
  final String id;
  Map<String, dynamic> toJson() => _\$InvoiceToJson(this);
}
''',
        ['VernakCoupon', 'fromJson', 'toJson', 'fromJson'],
        after: 'class VernakCoupon',
      );

  Future<void> test_class_without_json_members_is_clean() =>
      expectIn('model/promo_code_draft.dart', 'class PromoCodeDraft {\n  const PromoCodeDraft();\n}\n', []);

  Future<void> test_outside_the_model_role_is_left_to_models_only_in_model() => expectIn(
        'utils/helpers/ares_service.dart',
        "class AresCompanyData {\n  Map<String, dynamic> toJson() => {};\n}\n",
        [],
      );

  Future<void> test_layout_override_of_the_model_role() async {
    newFile('$testPackageRootPath/neon_check.yaml', 'layout:\n  model: [lib/data/]\n');
    await expectIn('data/user.dart', "class User {\n  Map<String, dynamic> toJson() => {};\n}\n", ['User', 'toJson']);
  }
}

@reflectiveTest
class NoDynamicInModelsTest extends _SerializationTest {
  @override
  AnalysisRule get ruleUnderTest => NoDynamicInModels();

  Future<void> test_loose_types_are_flagged() => expectIn(
        'model/user.dart',
        '''
class User {
  User(this.metadata, {required this.tags, this.raw, Object? extra, Map<String, Object?>? settings});
  factory User.fromJson(Map<String, dynamic> json) => User(const {}, tags: const []);
  factory User.fromEnvelope(Map<String, dynamic> data) => User(const {}, tags: const []);
  final Map<String, dynamic> metadata;
  final List<dynamic> tags;
  final dynamic raw;
  Object? get payload => raw;
  List<Map<String, dynamic>> get rows => const [];
  Map<String, dynamic> toJson() => metadata;
}
''',
        ['extra', 'settings', 'data', 'metadata', 'tags', 'raw', 'payload', 'rows'],
        after: 'User(this.metadata,',
        message: ['a model field, constructor parameter or getter has a concrete type'],
      );

  Future<void> test_concrete_types_are_clean() => expectIn(
        'model/vernak/vernak_post.dart',
        '''
enum VernakPostType { photo, text }

class VernakPost<T> {
  const VernakPost(this.id, this.type, this.data, {this.tags = const [], this.counts = const {}});
  final String id;
  final VernakPostType type;
  final T data;
  final List<String> tags;
  final Map<String, int> counts;
  String get title => id;
}
''',
        [],
      );

  Future<void> test_overridden_getters_take_their_supertype() => expectIn(
        'model/request_models/vernak/coupons/create_coupon_request.dart',
        '''
abstract class Request {
  Map<String, dynamic>? get body => null;
}

class CreateCouponRequest extends Request {
  CreateCouponRequest(this.name);
  final String name;
  @override
  Map<String, dynamic>? get body => {'name': name};
}
''',
        ['body'],
        message: ['the getter body of Request'],
      );

  Future<void> test_an_unannotated_override_takes_its_supertype() => expectIn(
        'model/request_models/vernak/coupons/get_coupons_request.dart',
        '''
abstract class Request {
  Map<String, dynamic>? get queryParameters => null;
}

class GetCouponsRequest extends Request {
  GetCouponsRequest(this.query);
  final String query;
  Map<String, dynamic> get queryParameters => {'q': query};
  Map<String, dynamic> get extra => {'q': query};
}
''',
        ['queryParameters', 'extra'],
      );

  Future<void> test_outside_the_model_role_is_clean() => expectIn('bloc/cards/cards_state.dart',
      'class CardsLoaded {\n  const CardsLoaded(this.raw);\n  final dynamic raw;\n}\n', []);
}

/// A `JsonConverter` has fromJson / toJson and is no model, inside or outside
/// the model role.
@reflectiveTest
class JsonConverterIsNoModelTest extends _SerializationTest {
  @override
  AnalysisRule get ruleUnderTest => ModelsOnlyInModel();

  static const _converter = '''
${_json}class HexConverter implements JsonConverter<int, String> {
  const HexConverter();
  @override
  int fromJson(String json) => json.length;
  @override
  String toJson(int object) => '\$object';
}
''';

  Future<void> test_converter_outside_model_is_clean() => expectIn('utils/helpers/hex_converter.dart', _converter, []);
}

@reflectiveTest
class JsonConverterInModelTest extends _SerializationTest {
  @override
  AnalysisRule get ruleUnderTest => ModelUsesJsonSerializable();

  Future<void> test_converter_is_no_model_for_json_serializable() =>
      expectIn('model/converters/hex_converter.dart', JsonConverterIsNoModelTest._converter, []);
}
