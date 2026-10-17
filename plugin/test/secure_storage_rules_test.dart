import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:neon_lints/src/secure_storage_rules.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/bloc_rule_base.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(SecureStorageOnlyInRepositoryTest);
    defineReflectiveTests(SecureStorageOptionsTest);
    defineReflectiveTests(SecureStorageKeysTest);
  });
}

const _plugin = '''
enum KeychainAccessibility { first_unlock }

class AndroidOptions {
  const AndroidOptions({String? sharedPreferencesName, String? storageNamespace});
}

class IOSOptions {
  const IOSOptions({String? accountName, KeychainAccessibility? accessibility});
}

class MacOsOptions {
  const MacOsOptions({String? accountName, KeychainAccessibility? accessibility});
}

class WebOptions {
  const WebOptions({String dbName = 'FlutterEncryptedStorage', String publicKey = 'FlutterSecureStorage'});
}

class FlutterSecureStorage {
  const FlutterSecureStorage({AndroidOptions? aOptions, IOSOptions? iOptions, MacOsOptions? mOptions, WebOptions? webOptions});
  Future<String?> read({required String key, WebOptions? webOptions}) async => null;
  Future<void> write({required String key, required String? value}) async {}
}
''';

const _import = "import 'package:flutter_secure_storage/flutter_secure_storage.dart';\n\n";

const _complete = '''
FlutterSecureStorage(
    aOptions: AndroidOptions(storageNamespace: 'AppPrefs'),
    iOptions: IOSOptions(accountName: 'AppKeychain', accessibility: KeychainAccessibility.first_unlock),
    mOptions: MacOsOptions(accountName: 'AppKeychain', accessibility: KeychainAccessibility.first_unlock),
    webOptions: WebOptions(dbName: 'AppSecure', publicKey: 'App'),
  )''';

const _repository = 'repository/shared_prefs_repository.dart';

/// The secure-storage rules with a flutter_secure_storage stub and the app's
/// allow-list of secret keys.
abstract class _SecureStorageTest extends BlocRuleTest {
  @override
  void setUp() {
    newPackage('flutter_secure_storage').addFile('lib/flutter_secure_storage.dart', _plugin);
    super.setUp();
    newFile('$testPackageRootPath/neon_check.yaml', 'secure_storage_keys: [key_auth_token, key_refresh_token]\n');
  }
}

@reflectiveTest
class SecureStorageOnlyInRepositoryTest extends _SecureStorageTest {
  @override
  AnalysisRule get ruleUnderTest => SecureStorageOnlyInRepository();

  Future<void> test_the_repository_owns_the_store() =>
      expectIn(_repository, '${_import}const storage = $_complete;\n', []);

  Future<void> test_a_store_elsewhere_is_flagged() => expectIn(
        'bloc/session/session_cubit.dart',
        '${_import}const storage = $_complete;\n',
        ['FlutterSecureStorage'],
      );
}

@reflectiveTest
class SecureStorageOptionsTest extends _SecureStorageTest {
  @override
  AnalysisRule get ruleUnderTest => SecureStorageOptions();

  Future<void> test_every_option_set_is_clean() async {
    await expectIn(_repository, '${_import}const storage = $_complete;\n', []);
  }

  Future<void> test_the_legacy_android_name_is_accepted() => expectIn(
        _repository,
        '''
${_import}const storage = FlutterSecureStorage(
  aOptions: AndroidOptions(sharedPreferencesName: 'AppPrefs'),
  iOptions: IOSOptions(accountName: 'AppKeychain', accessibility: KeychainAccessibility.first_unlock),
  mOptions: MacOsOptions(accountName: 'AppKeychain', accessibility: KeychainAccessibility.first_unlock),
  webOptions: WebOptions(dbName: 'AppSecure'),
);
''',
        [],
      );

  Future<void> test_missing_options_are_flagged() => expectIn(
        _repository,
        '''
${_import}const storage = FlutterSecureStorage(
  aOptions: AndroidOptions(),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock),
);
''',
        ['FlutterSecureStorage'],
        message: [
          'AndroidOptions(storageNamespace or sharedPreferencesName:)',
          'IOSOptions(accountName:)',
          'webOptions'
        ],
      );
}

@reflectiveTest
class SecureStorageKeysTest extends _SecureStorageTest {
  @override
  AnalysisRule get ruleUnderTest => SecureStorageKeys();

  Future<void> test_secret_keys_are_clean() => expectIn(
        _repository,
        '''
${_import}class Store {
  static const _storage = $_complete;
  static const keyAuthToken = 'key_auth_token';

  static String scope(String project) => project;
  static String _tokenKey(String project) => '\${keyAuthToken}_\${scope(project)}';

  Future<void> saveToken(String token, String project) => _storage.write(key: _tokenKey(project), value: token);
  Future<void> saveRefresh(String token) => _storage.write(key: 'key_refresh_token', value: token);
}
''',
        [],
      );

  Future<void> test_settings_and_unknown_keys_are_flagged() => expectIn(
        _repository,
        '''
${_import}class Store {
  static const _storage = $_complete;
  static const _keyLocale = 'key_locale_code';

  Future<void> saveLocale(String code) => _storage.write(key: _keyLocale, value: code);
  Future<void> save(String value) => _storage.write(key: dynamicKey, value: value);
  String dynamicKey = 'key_auth_token';
}
''',
        ['_keyLocale', 'dynamicKey'],
        after: 'saveLocale',
      );
}
