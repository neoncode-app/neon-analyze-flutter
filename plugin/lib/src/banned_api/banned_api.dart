import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

/// One row of a banned-API table: which API is banned, what replaces it, and
/// which files own it (may still use it, because they implement the
/// replacement).
///
/// Matching is type-resolved: an API is identified by its element name AND
/// the package that declares it, so an app class that happens to be called
/// `Switch` is never flagged, and an import alias or prefix does not hide a
/// banned one.
///
/// What a row flags:
///  * [types] — constructing the class (any constructor, or only the ones in
///    [constructors]), a constructor tear-off, and every access to a static
///    member (`Icons.add`, `Navigator.of(context)`, `Clipboard.setData(...)`).
///    Type annotations are never flagged: holding a value of the type is fine,
///    building or calling it is not. `'*'` means every class of [package].
///  * [functions] — calling a top-level function of [package] (`showDialog`).
///  * [bansImport] — importing any library of [package] (`package:fl_chart`).
final class BannedApi {
  const BannedApi({
    required this.label,
    required this.replacement,
    this.package = 'flutter',
    this.types = const {},
    this.constructors,
    this.onlyWithArgs = const {},
    this.functions = const {},
    this.bansImport = false,
    this.owners = const [],
    this.ownerCategory,
  });

  /// How the banned API is named in the message, e.g. `Container(decoration:)`.
  final String label;

  /// What to use instead; named in the message, e.g. `RoundedContainer`.
  final String replacement;

  /// Package that declares the banned API (`flutter`, `intl`, `fl_chart`).
  final String package;

  /// Banned classes of [package]; `'*'` bans every class of the package.
  final Set<String> types;

  /// When set, only these constructors of [types] are banned (`'new'` is the
  /// unnamed one). Static member access is then not flagged.
  final Set<String>? constructors;

  /// When non-empty, a construction is flagged only if it passes one of these
  /// named arguments (`Container` only with `decoration:`).
  final Set<String> onlyWithArgs;

  /// Banned top-level functions of [package].
  final Set<String> functions;

  /// Whether importing [package] at all is banned.
  final bool bansImport;

  /// Files and folders, relative to `lib/`, that may use the API. A folder
  /// ends with `/`.
  final List<String> owners;

  /// A file that declares a class whose doc comment carries
  /// `{@category <ownerCategory>}` may use the API, so a new template counts
  /// without editing the table.
  final String? ownerCategory;

  /// Whether the file at [path] (normalised to `/`) owns this API.
  bool isOwner(String path, CompilationUnit unit) {
    for (final owner in owners) {
      final fragment = '/lib/$owner';
      if (owner.endsWith('/') ? path.contains(fragment) : path.endsWith(fragment)) {
        return true;
      }
    }
    final category = ownerCategory;
    return category != null && declaresCategory(unit, category);
  }

  bool _isPackageLibrary(Element? element) => element?.library?.uri.toString().startsWith('package:$package/') ?? false;

  /// Whether [element] is one of the banned classes.
  bool bansClass(Element? element) =>
      element is InterfaceElement &&
      _isPackageLibrary(element) &&
      (types.contains('*') || types.contains(element.name));

  /// Whether constructing via [constructor] is banned (arguments aside).
  bool bansConstructor(ConstructorElement? constructor) {
    if (constructor == null || !bansClass(constructor.enclosingElement)) return false;
    final allowed = constructors;
    return allowed == null || allowed.contains(constructor.name);
  }

  /// Whether a static member access on the class [element] is banned.
  bool bansStaticAccess(Element? element) => constructors == null && bansClass(element);

  /// Whether [element] is a banned top-level function.
  bool bansFunction(Element? element) =>
      element is TopLevelFunctionElement && _isPackageLibrary(element) && functions.contains(element.name);

  /// Whether importing [uri] is banned.
  bool bansImportOf(String? uri) => bansImport && (uri?.startsWith('package:$package/') ?? false);
}

/// Whether [unit] declares a class whose doc comment ends in
/// `{@category <category>}`.
bool declaresCategory(CompilationUnit unit, String category) {
  final marker = '{@category $category}';
  for (final declaration in unit.declarations) {
    final comment = declaration.documentationComment;
    if (comment == null) continue;
    if (comment.tokens.any((token) => token.lexeme.contains(marker))) return true;
  }
  return false;
}

/// A rule driven by a table of [BannedApi] rows. Each diagnostic names the
/// banned API and its replacement, so the message is the documentation.
///
/// Only files under `lib/` are checked, and generated files are skipped.
///
/// The [LintCode] of a subclass must take two message arguments: `{0}` is the
/// banned API's label, `{1}` its replacement.
abstract class BannedApiRule extends AnalysisRule {
  BannedApiRule({required super.name, required super.description});

  /// The rows this rule enforces.
  List<BannedApi> get table;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    final visitor = _Visitor(this);
    registry
      ..addInstanceCreationExpression(this, visitor)
      ..addConstructorReference(this, visitor)
      ..addMethodInvocation(this, visitor)
      ..addPrefixedIdentifier(this, visitor)
      ..addPropertyAccess(this, visitor)
      ..addImportDirective(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final BannedApiRule rule;

  /// Reports [node] for the first row [matches] accepts, unless the file is
  /// generated or owns that row.
  void _check(AstNode node, bool Function(BannedApi row) matches) {
    final unit = node.root;
    if (unit is! CompilationUnit) return;
    final path = (unit.declaredFragment?.source.fullName ?? '').replaceAll(r'\', '/');
    // App code only: widget tests under test/ pump raw MaterialApp/Scaffold.
    if (!path.contains('/lib/')) return;
    // The plugin API (0.3.10) does not honour the analyzer `exclude` globs.
    if (path.endsWith('.g.dart') || path.endsWith('.freezed.dart')) return;
    for (final row in rule.table) {
      if (!matches(row)) continue;
      if (row.isOwner(path, unit)) return;
      rule.reportAtNode(node, arguments: [row.label, row.replacement]);
      return;
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final constructor = node.constructorName.element;
    _check(node.constructorName, (row) {
      if (!row.bansConstructor(constructor)) return false;
      if (row.onlyWithArgs.isEmpty) return true;
      return node.argumentList.arguments.any(
        (argument) => argument is NamedExpression && row.onlyWithArgs.contains(argument.name.label.name),
      );
    });
  }

  @override
  void visitConstructorReference(ConstructorReference node) {
    final constructor = node.constructorName.element;
    _check(node, (row) => row.onlyWithArgs.isEmpty && row.bansConstructor(constructor));
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final function = node.methodName.element;
    if (function is TopLevelFunctionElement) {
      _check(node.methodName, (row) => row.bansFunction(function));
      return;
    }
    // `Navigator.of(context)`, `material.Clipboard.setData(...)`.
    final target = node.target;
    if (target is Identifier) {
      _check(node, (row) => row.bansStaticAccess(target.element));
    }
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    // `Icons.add`, `Navigator.pop` (tear-off). An import prefix (`m.Icons`)
    // resolves to a prefix element, never a banned class.
    _check(node, (row) => row.bansStaticAccess(node.prefix.element));
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    // `m.Icons.add`: the target is `m.Icons`.
    final target = node.target;
    if (target is PrefixedIdentifier) {
      _check(node, (row) => row.bansStaticAccess(target.element));
    }
  }

  @override
  void visitImportDirective(ImportDirective node) {
    final uri = node.uri.stringValue;
    _check(node, (row) => row.bansImportOf(uri));
  }
}

/// The message shape every [BannedApiRule] shares: `{0}` label, `{1}`
/// replacement.
LintCode bannedApiCode(String name, {required String what}) => LintCode(
      name,
      '[NEON] {0} is $what; use {1}.',
      correctionMessage: 'Replace it with {1}.',
      severity: DiagnosticSeverity.WARNING,
    );
