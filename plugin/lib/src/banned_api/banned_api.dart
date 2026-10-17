import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/layer_folders.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// Which code a [BannedApi] row applies to, on top of its owners.
enum BannedScope {
  /// Every app source file.
  all,

  /// UI code only: pages, features and the widget kit ([RuleLayout.isUi]).
  ui,

  /// Everything except UI code (where a UI-only rule already reports it).
  outsideUi,
}

/// An extra condition on the matched node (the construction, the call, or the
/// identifier), for a row the API's identity alone cannot decide: a `RegExp`
/// only with an e-mail pattern, a `Timer` only when stored in a field. A
/// top-level function, so a row stays `const`.
typedef BannedApiCondition = bool Function(AstNode node);

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
///  * [methods] — calling an instance method of one of [types]
///    (`x.toStringAsFixed(2)` on `num` / `double` of `dart:core`); with
///    [methods] set, [types] only names the declaring classes.
///  * [variables] — reading a top-level variable or getter of [package]
///    (`kIsWeb`).
///  * [bansImport] — importing any library of [package] (`package:fl_chart`).
///  * [subclassing] — naming one of [types] in an `extends`, `with`,
///    `implements` or mixin `on` clause (`class X extends ChangeNotifier`);
///    with `constructors: {}` a row bans only that.
///
/// [package] is a pub package name (`flutter`, `intl`) or an SDK library
/// (`dart:io`, `dart:convert`). [scope], [onlyIn] and [exceptIn] limit the
/// row to some code (layout roles), and [when] adds a condition on the node.
final class BannedApi {
  const BannedApi({
    required this.label,
    required this.replacement,
    this.package = 'flutter',
    this.types = const {},
    this.constructors,
    this.onlyWithArgs = const {},
    this.functions = const {},
    this.methods = const {},
    this.variables = const {},
    this.bansImport = false,
    this.subclassing = false,
    this.owners = const [],
    this.ownerCategory,
    this.ownerClasses = const {},
    this.scope = BannedScope.all,
    this.onlyIn = const {},
    this.exceptIn = const {},
    this.when,
  });

  /// How the banned API is named in the message, e.g. `Container(decoration:)`.
  final String label;

  /// What to use instead; named in the message, e.g. `RoundedContainer`.
  final String replacement;

  /// Package that declares the banned API (`flutter`, `intl`, `fl_chart`), or
  /// an SDK library (`dart:io`).
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

  /// Banned instance methods of [types].
  final Set<String> methods;

  /// Banned top-level variables and getters of [package].
  final Set<String> variables;

  /// Whether importing [package] at all is banned.
  final bool bansImport;

  /// Whether extending, mixing in or implementing one of [types] is banned.
  final bool subclassing;

  /// Files and folders, relative to `lib/`, that may use the API. A folder
  /// ends with `/`.
  final List<String> owners;

  /// A file that declares a class whose doc comment carries
  /// `{@category <ownerCategory>}` may use the API, so a new template counts
  /// without editing the table.
  final String? ownerCategory;

  /// A file that declares one of these classes may use the API (the kit
  /// widget that wraps it), wherever the app keeps that widget.
  final Set<String> ownerClasses;

  /// Which code the row applies to.
  final BannedScope scope;

  /// When non-empty, the row applies only to files in one of these roles.
  final Set<LayoutRole> onlyIn;

  /// Files in one of these roles may use the API (the layer that owns it).
  final Set<LayoutRole> exceptIn;

  /// An extra condition on the matched node; `null` accepts every match.
  final BannedApiCondition? when;

  /// Whether the row applies to the file at [path] of [layout] (scope and
  /// roles; owners are separate).
  bool appliesTo(String path, RuleLayout layout) {
    switch (scope) {
      case BannedScope.all:
        break;
      case BannedScope.ui:
        if (!layout.isUi(path)) return false;
      case BannedScope.outsideUi:
        if (layout.isUi(path)) return false;
    }
    if (onlyIn.isNotEmpty && !onlyIn.any((role) => layout.isIn(path, role))) return false;
    return !exceptIn.any((role) => layout.isIn(path, role));
  }

  /// Whether the file at [path] (normalised to `/`) owns this API.
  bool isOwner(String path, CompilationUnit unit) {
    // Owners name a piece by its folder (`global_widgets/global/app_tap_area/`);
    // the layer folders of NCC0000058 (`components/`, `patterns/`, ...) sit
    // between the kit and the piece, so they are left out of the comparison.
    final bare = withoutLayerFolders(path);
    for (final owner in owners) {
      final fragment = '/lib/$owner';
      for (final candidate in {path, bare}) {
        if (owner.endsWith('/') ? candidate.contains(fragment) : candidate.endsWith(fragment)) {
          return true;
        }
      }
    }
    if (ownerClasses.isNotEmpty && declaresClass(unit, ownerClasses)) return true;
    final category = ownerCategory;
    return category != null && declaresCategory(unit, category);
  }

  bool _isPackageLibrary(Element? element) {
    final uri = element?.library?.uri.toString();
    if (uri == null) return false;
    return package.startsWith('dart:') ? uri == package : uri.startsWith('package:$package/');
  }

  /// Whether [element] is one of the banned classes.
  bool bansClass(Element? element) =>
      element is InterfaceElement &&
      _isPackageLibrary(element) &&
      (types.contains('*') || types.contains(element.name));

  /// Whether constructing via [constructor] is banned (arguments aside).
  bool bansConstructor(ConstructorElement? constructor) {
    if (constructor == null || !bansClass(constructor.enclosingElement)) return false;
    final allowed = constructors;
    return methods.isEmpty && (allowed == null || allowed.contains(constructor.name));
  }

  /// Whether a static member access on the class [element] is banned.
  bool bansStaticAccess(Element? element) => constructors == null && methods.isEmpty && bansClass(element);

  /// Whether calling the instance method [element] is banned.
  bool bansMethod(Element? element) =>
      element is MethodElement &&
      !element.isStatic &&
      methods.contains(element.name) &&
      bansClass(element.enclosingElement);

  /// Whether reading [element] (a top-level variable or its getter) is banned.
  bool bansVariable(Element? element) {
    if (variables.isEmpty) return false;
    final variable = element is PropertyAccessorElement ? element.variable : element;
    return variable is TopLevelVariableElement && variables.contains(variable.name) && _isPackageLibrary(variable);
  }

  /// Whether [element] is a banned top-level function.
  bool bansFunction(Element? element) =>
      element is TopLevelFunctionElement && _isPackageLibrary(element) && functions.contains(element.name);

  /// Whether naming [element] as a supertype (`extends` / `with` /
  /// `implements` / `on`) is banned.
  bool bansSubtypeOf(Element? element) => subclassing && bansClass(element);

  /// Whether importing [uri] is banned.
  bool bansImportOf(String? uri) => bansImport && (uri?.startsWith('package:$package/') ?? false);
}

/// Whether [unit] declares a class named one of [names].
bool declaresClass(CompilationUnit unit, Set<String> names) => unit.declarations.any(
      (declaration) => declaration is ClassDeclaration && names.contains(declaration.declaredFragment?.element.name),
    );

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
    final visitor = _Visitor(this, RuleLayout.of(context));
    registry
      ..addInstanceCreationExpression(this, visitor)
      ..addConstructorReference(this, visitor)
      ..addMethodInvocation(this, visitor)
      ..addPrefixedIdentifier(this, visitor)
      ..addPropertyAccess(this, visitor)
      ..addImportDirective(this, visitor);
    if (table.any((row) => row.variables.isNotEmpty)) registry.addSimpleIdentifier(this, visitor);
    if (table.any((row) => row.subclassing)) registry.addNamedType(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.layout);

  final BannedApiRule rule;

  final RuleLayout layout;

  /// Reports [node] for the first row [matches] accepts (and whose scope and
  /// condition, checked on [subject], hold), unless the file is generated or
  /// owns that row.
  void _check(AstNode node, bool Function(BannedApi row) matches, {AstNode? subject}) {
    final unit = node.root;
    if (unit is! CompilationUnit) return;
    final path = (unit.declaredFragment?.source.fullName ?? '').replaceAll(r'\', '/');
    // App code only: widget tests under test/ pump raw MaterialApp/Scaffold.
    if (!path.contains('/lib/')) return;
    // The plugin API (0.3.10) does not honour the analyzer `exclude` globs.
    if (path.endsWith('.g.dart') || path.endsWith('.freezed.dart')) return;
    for (final row in rule.table) {
      if (!matches(row)) continue;
      if (!row.appliesTo(path, layout)) continue;
      final condition = row.when;
      if (condition != null && !condition(subject ?? node)) continue;
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
    }, subject: node);
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
      _check(node.methodName, (row) => row.bansFunction(function), subject: node);
      return;
    }
    // `price.toStringAsFixed(2)`.
    if (function is MethodElement && !function.isStatic) {
      _check(node, (row) => row.bansMethod(function));
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
  void visitSimpleIdentifier(SimpleIdentifier node) {
    // `kIsWeb`, also as `foundation.kIsWeb`; not in `show kIsWeb`.
    if (node.parent is Combinator) return;
    final element = node.element;
    if (element is! PropertyAccessorElement && element is! TopLevelVariableElement) return;
    _check(node, (row) => row.bansVariable(element));
  }

  @override
  void visitNamedType(NamedType node) {
    // `class X extends ChangeNotifier`, `with ChangeNotifier`, `implements`,
    // `mixin M on Bloc<E, S>`; a type annotation is never flagged.
    final parent = node.parent;
    if (parent is! ExtendsClause && parent is! WithClause && parent is! ImplementsClause && parent is! MixinOnClause) {
      return;
    }
    final element = node.element;
    _check(node, (row) => row.bansSubtypeOf(element));
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
