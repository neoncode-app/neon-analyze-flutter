import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/request_model_rules.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(RequestExtendsProjectBaseTest);
    defineReflectiveTests(NoTenantInExtraHeadersTest);
  });
}

const _neonapi = '''
abstract class NeoRequest<T> {
  String get endpoint;
  String? get project => null;
  Map<String, String>? get extraHeaders => null;
}
''';

const _api = "import 'package:neonapi/neonapi.dart';\n\n";

/// The request rules with a neonapi stub and the project bases of an app.
abstract class _RequestTest extends BlocRuleTest {
  @override
  void setUp() {
    newPackage('neonapi').addFile('lib/neonapi.dart', _neonapi);
    super.setUp();
    newFile('$testPackageLibPath/model/request_models/_base/vernak_request.dart', '''
${_api}abstract class VernakRequest<T> extends NeoRequest<T> {
  @override
  String get project => 'vernakProd';
}
''');
    newFile('$testPackageLibPath/model/request_models/_base/tenant_scoped_request.dart', '''
${_api}abstract class TenantScopedRequest<T> extends NeoRequest<T> {
  TenantScopedRequest({this.project});
  @override
  final String? project;
}
''');
  }
}

const _bases = "import 'package:test/model/request_models/_base/vernak_request.dart';\n"
    "import 'package:test/model/request_models/_base/tenant_scoped_request.dart';\n";

@reflectiveTest
class RequestExtendsProjectBaseTest extends _RequestTest {
  @override
  AnalysisRule get ruleUnderTest => RequestExtendsProjectBase();

  Future<void> test_request_on_its_project_base_is_clean() => expectIn(
        'model/request_models/vernak/coupons/get_coupons_request.dart',
        '''
$_api${_bases}class GetCouponsRequest extends VernakRequest<String> {
  @override
  String get endpoint => '/api/coupons';
}
''',
        [],
      );

  Future<void> test_tenant_scoped_request_is_clean_in_any_folder() => expectIn(
        'model/request_models/vernak/engagements/get_engagement_request.dart',
        '''
$_api${_bases}class GetEngagementRequest extends TenantScopedRequest<String> {
  GetEngagementRequest({super.project});
  @override
  String get endpoint => '/api/engagements';
}
''',
        [],
      );

  Future<void> test_common_request_extends_neo_request() => expectIn(
        'model/request_models/common/auth/login_request.dart',
        '''
$_api${_bases}class LoginRequest extends NeoRequest<String> {
  @override
  String get endpoint => '/api/auth/login';
}

class MeRequest extends VernakRequest<String> {
  @override
  String get endpoint => '/api/users/me';
}
''',
        ['MeRequest'],
        message: ['does not extend NeoRequest'],
      );

  Future<void> test_request_without_its_project_base_is_flagged() => expectIn(
        'model/request_models/doordrop/businesses/get_businesses_request.dart',
        '''
$_api${_bases}class GetBusinessesRequest extends VernakRequest<String> {
  @override
  String get endpoint => '/api/doordrop/businesses';
}
''',
        ['GetBusinessesRequest'],
        message: ['_base/doordrop_request.dart'],
      );

  Future<void> test_flat_request_and_own_project_are_flagged() => expectIn(
        'model/request_models/vernak_requests.dart',
        '''
${_api}class GetCompaniesRequest extends NeoRequest<String> {
  @override
  String get endpoint => '/api/companies';

  @override
  String get project => 'vernakProd';
}

class GetEngagementRequest extends NeoRequest<String> {
  @override
  final String? project;

  GetEngagementRequest({this.project});

  @override
  String get endpoint => '/api/engagements';
}

class CouponDraft {
  const CouponDraft(this.project);
  final String project;
}
''',
        ['GetCompaniesRequest', 'project', 'GetEngagementRequest', 'project'],
      );

  Future<void> test_bases_may_set_project() => expectIn(
        'model/request_models/_base/quest_request.dart',
        '''
${_api}abstract class QuestRequest<T> extends NeoRequest<T> {
  @override
  String get project => 'momentProd';
}
''',
        [],
      );

  Future<void> test_outside_request_models_is_clean() => expectIn(
        'repository/raw_request.dart',
        '''
${_api}class RawRequest extends NeoRequest<String> {
  @override
  String get endpoint => '/raw';
  @override
  String get project => 'x';
}
''',
        [],
      );
}

@reflectiveTest
class NoTenantInExtraHeadersTest extends _RequestTest {
  @override
  AnalysisRule get ruleUnderTest => NoTenantInExtraHeaders();

  Future<void> test_tenant_header_is_flagged() => expectIn(
        'model/request_models/vernak/banners/get_banners_request.dart',
        '''
${_api}const projectHeader = 'x-project';

class GetBannersRequest extends NeoRequest<String> {
  @override
  String get endpoint => '/api/banners';

  @override
  Map<String, String>? get extraHeaders => {'X-Project': 'vernakProd'};
}

class GetBannerRequest extends NeoRequest<String> {
  @override
  String get endpoint => '/api/banners/1';

  @override
  Map<String, String>? get extraHeaders => {projectHeader: 'vernakProd'};
}
''',
        ['extraHeaders', 'extraHeaders'],
      );

  Future<void> test_other_headers_are_clean() => expectIn(
        'model/request_models/vernak/banners/get_banners_request.dart',
        '''
${_api}class GetBannersRequest extends NeoRequest<String> {
  @override
  String get endpoint => '/api/banners';

  @override
  Map<String, String>? get extraHeaders => {'x-locale': 'cs'};
}
''',
        [],
      );
}
