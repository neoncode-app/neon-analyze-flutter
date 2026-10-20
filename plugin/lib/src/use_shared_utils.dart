import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/banned_api/banned_api.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// Bans the raw APIs that `package:neon_flutter_utils` wraps, and names the
/// helper and its library to use instead, so a formatter, validator, URL
/// opener or debounce is written once in the package (with a test) and never
/// again in a page or a cubit.
///
/// The table below is the whole rule: one [BannedApi] row per banned API.
/// Nothing in an app owns these APIs (the package does), except the kit
/// widgets that wrap the clipboard and the repository layer, which decodes
/// API JSON. Matching is type-resolved (declaring package or SDK library), so
/// an app class called `DateFormat` or `Timer` is not flagged.
///
/// Source of the table: ticket NCR0000030, "neon_flutter_utils is the only way".
class UseSharedUtils extends BannedApiRule {
  UseSharedUtils() : super(name: 'use_shared_utils', description: _desc);

  static const _desc = 'Use the neon_flutter_utils helpers instead of the raw APIs they wrap.';

  static final LintCode code = bannedApiCode('use_shared_utils', what: 'a raw API that neon_flutter_utils wraps');

  static const _utils = 'package:neon_flutter_utils';

  static const rows = <BannedApi>[
    BannedApi(
      label: 'DateFormat( / NumberFormat(',
      replacement: 'formatAppDate / formatAppDateTime / formatAppTime / formatTimeOfDay / formatDecimal / '
          'formatMoney / formatPercent ... from $_utils/format.dart',
      package: 'intl',
      types: {'DateFormat', 'NumberFormat'},
    ),
    BannedApi(
      label: 'toStringAsFixed( in UI code',
      replacement: 'formatDecimal / formatMoney / formatPercent from $_utils/format.dart',
      package: 'dart:core',
      types: {'num', 'double', 'int'},
      methods: {'toStringAsFixed'},
      scope: BannedScope.ui,
    ),
    BannedApi(
      label: 'launchUrl( / launchUrlString( / canLaunchUrl(',
      replacement: 'openExternalUrl / openExternalUri from $_utils/links.dart',
      package: 'url_launcher',
      functions: {'launchUrl', 'launchUrlString', 'canLaunchUrl', 'canLaunchUrlString'},
    ),
    BannedApi(
      label: 'Clipboard.',
      replacement: 'AppCopyButton / AppCopyField (the kit widgets that wrap the clipboard)',
      types: {'Clipboard'},
      ownerClasses: {'AppCopyButton', 'AppCopyField'},
    ),
    BannedApi(
      label: 'jsonDecode( outside the repository layer',
      replacement: 'tryDecodeMap / tryDecodeList from $_utils/json.dart',
      package: 'dart:convert',
      functions: {'jsonDecode'},
      exceptIn: {LayoutRole.repository},
    ),
    BannedApi(
      label: 'RegExp( with an e-mail or phone pattern',
      replacement: 'validateEmail / validatePhone from $_utils/validation.dart '
          '(or String.isValidEmail from $_utils/text.dart)',
      package: 'dart:core',
      types: {'RegExp'},
      when: isContactPattern,
    ),
    BannedApi(
      label: 'kIsWeb outside UI code',
      replacement: 'PlatformCapabilities from $_utils/platform.dart',
      variables: {'kIsWeb'},
      scope: BannedScope.outsideUi,
    ),
    BannedApi(
      label: 'Platform. (dart:io) outside UI code',
      replacement: 'PlatformCapabilities from $_utils/platform.dart',
      package: 'dart:io',
      types: {'Platform'},
      scope: BannedScope.outsideUi,
    ),
    BannedApi(
      label: 'Timer( stored in a cubit field (a debounce)',
      replacement: 'Debouncer from $_utils/async.dart',
      package: 'dart:async',
      types: {'Timer'},
      constructors: {'new'},
      onlyIn: {LayoutRole.bloc},
      when: isDebounceTimer,
    ),
  ];

  @override
  List<BannedApi> get table => rows;

  @override
  DiagnosticCode get diagnosticCode => code;
}

/// Whether [node] is a `RegExp(...)` whose literal pattern validates an e-mail
/// address or a phone number, the two validators of
/// `neon_flutter_utils/validation.dart`.
///
/// Deliberately simple, so it is predictable:
///  * e-mail: the pattern contains `@` together with `\.` or a letter class
///    (`[a-zA-Z` / `[A-Za-z`);
///  * phone: an optional leading plus followed by digits (`\+?[0-9`,
///    `\+?\d`), or a run of nine digits (`\d{9`, `[0-9]{9`), the length of a
///    Czech or Slovak number.
///
/// A pattern built by interpolation is never flagged.
bool isContactPattern(AstNode node) {
  if (node is! InstanceCreationExpression) return false;
  final arguments = node.argumentList.arguments;
  if (arguments.isEmpty) return false;
  final first = arguments.first;
  if (first is! StringLiteral) return false;
  final pattern = first.stringValue;
  if (pattern == null) return false;
  final email =
      pattern.contains('@') && (pattern.contains(r'\.') || pattern.contains('[a-zA-Z') || pattern.contains('[A-Za-z'));
  final phone = pattern.contains(r'\+?[0-9') ||
      pattern.contains(r'\+?\d') ||
      pattern.contains(r'\d{9') ||
      pattern.contains('[0-9]{9');
  return email || phone;
}

/// Whether [node] is a hand-made debounce: a `Timer(duration, ...)` stored in
/// a field ([isStoredInField]) whose duration is a constant (`const
/// Duration(...)`, `Duration.zero`, a `const` or `static final` field). A timer
/// armed for a computed moment (`next.difference(now)`) is a scheduler, not a
/// debounce, and Debouncer (one fixed duration) cannot replace it.
bool isDebounceTimer(AstNode node) {
  if (!isStoredInField(node) || node is! InstanceCreationExpression) return false;
  final arguments = node.argumentList.arguments;
  return arguments.isNotEmpty && _isConstantValue(arguments.first);
}

/// Whether [expression] always has the same value: a literal, a `const`
/// construction, or a read of a `const` / `static final` / top-level `final`
/// variable.
bool _isConstantValue(Expression expression) {
  final value = expression.unParenthesized;
  if (value is Literal) return true;
  if (value is InstanceCreationExpression) return value.isConst;
  final element = switch (value) {
    Identifier() => value.element,
    PropertyAccess() => value.propertyName.element,
    _ => null,
  };
  final variable = element is PropertyAccessorElement ? element.variable : element;
  return switch (variable) {
    FieldElement() => variable.isConst || (variable.isStatic && variable.isFinal),
    TopLevelVariableElement() => variable.isConst || variable.isFinal,
    LocalVariableElement() => variable.isConst,
    _ => false,
  };
}

/// Whether [node] is a construction assigned to a field (`_debounce =
/// Timer(...)`, `_timer ??= Timer(...)`, `this._timer = Timer(...)`), the
/// shape of a hand-made debounce. A local `Timer` and one passed on are not.
bool isStoredInField(AstNode node) {
  var expression = node;
  var parent = node.parent;
  while (parent is ParenthesizedExpression) {
    expression = parent;
    parent = parent.parent;
  }
  if (parent is VariableDeclaration) {
    return parent.initializer == expression && parent.declaredFragment?.element is FieldElement;
  }
  if (parent is! AssignmentExpression || parent.rightHandSide != expression) return false;
  final element = parent.writeElement;
  final variable = element is PropertyAccessorElement ? element.variable : element;
  return variable is FieldElement;
}
