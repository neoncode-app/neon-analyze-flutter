import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/layout.dart' show matchesLayoutPattern;
import 'package:neon_lints/src/piece_rules.dart' show snakeCase;
import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

// The model layout (NCC0000065, decided by Filip 2026-10-16):
//
//   lib/model/enums/<scope>/<name>.dart   one enum per file; <scope> is
//                                         common/ or a project (vernak/, ...)
//   lib/model/**                          one top-level declaration per file,
//                                         data only: no top-level functions,
//                                         no widgets, dimens or Flutter UI
//
// and a class that serializes (fromJson / toJson / @JsonSerializable) lives
// nowhere but in the model role.

String _dirOf(String path) => path.substring(0, path.lastIndexOf('/'));

String _stem(String path) {
  final name = path.substring(path.lastIndexOf('/') + 1);
  return name.endsWith('.dart') ? name.substring(0, name.length - '.dart'.length) : name;
}

/// Whether the file [path] (absolute) is named after [name]: its stem spells
/// the declaration, underscores aside (`doordrop_turn.dart` names
/// `DoorDropTurn`), a leading `_` of a private name ignored.
bool _namedAfter(String path, String name) {
  final bare = name.startsWith('_') ? name.substring(1) : name;
  return _stem(path).replaceAll('_', '') == bare.toLowerCase();
}

/// Every enum lives in `lib/model/enums/<scope>/<name>.dart`, one per file,
/// `<scope>` being `common/` or a project. That covers enums declared today
/// in pages, cubits, states, features, utils and other model folders, private
/// ones included. Only the widget kit's variant enums in its `*_dimens.dart`
/// files stay where they are (`AppSwitchVariant`); a variant enum of a page or
/// feature part is no kit.
class EnumInEnumsFolder extends AnalysisRule {
  EnumInEnumsFolder() : super(name: 'enum_in_enums_folder', description: _desc);

  static const _desc = 'Every enum lives in lib/model/enums/<scope>/<name>.dart, one enum per file.';

  static const LintCode code = LintCode(
    'enum_in_enums_folder',
    '[NEON] enum {0} {1}; move it to {2}.',
    correctionMessage: 'Declare every enum in its own file lib/model/enums/<scope>/<name>.dart, <scope> being common/ '
        'or the project (vernak/, neoncode/, ...); only the kit variant enums of '
        'lib/global_widgets/**/*_dimens.dart stay beside their widget.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addEnumDeclaration(this, _EnumVisitor(this, RuleLayout.of(context)));
  }
}

class _EnumVisitor extends SimpleAstVisitor<void> {
  _EnumVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    final path = unitPath(node);
    if (!layout.isAppSource(path)) return;
    final name = node.namePart.typeName.lexeme;
    final bare = name.startsWith('_') ? name.substring(1) : name;
    final target = 'its own file lib/model/enums/<scope>/${snakeCase(bare)}.dart '
        '(scope folders: ${layout.describe(LayoutRole.enums)})';
    if (layout.isIn(path, LayoutRole.globalWidgets)) {
      if (layout.isIn(path, LayoutRole.widgetDimens)) return;
      // A kit enum is a variant of its piece: it belongs in the piece's dimens.
      rule.reportAtToken(
        node.namePart.typeName,
        arguments: [
          name,
          'of the widget kit is declared outside a *_dimens.dart',
          "its kit piece's <piece>_dimens.dart as a public <Widget>Variant (re-exported by the widget), or to $target",
        ],
      );
      return;
    }
    final String problem;
    if (!layout.isIn(path, LayoutRole.enums)) {
      problem = 'is not in a scope folder of lib/model/enums/';
    } else if (!_directlyInScope(path)) {
      problem = 'is nested below its scope folder';
    } else if (!_namedAfter(path, name)) {
      problem = 'is in a file not named after it';
    } else {
      return;
    }
    rule.reportAtToken(node.namePart.typeName, arguments: [name, problem, target]);
  }

  /// Whether the folder of [path] is itself a scope folder of the role (a
  /// folder pattern `lib/model/enums/*/` matches the folder, not a deeper one).
  bool _directlyInScope(String path) {
    final folder = layout.relative(_dirOf(path));
    if (folder == null) return false;
    for (final pattern in layout.layout.patterns(LayoutRole.enums)) {
      if (!pattern.endsWith('/')) return true;
      if (matchesLayoutPattern(pattern.substring(0, pattern.length - 1), folder)) return true;
    }
    return false;
  }
}

/// One top-level declaration (a class, enum, mixin, extension, extension type
/// or typedef) per file of the model role; generated parts are skipped. One
/// request per file, one enum per file, one extension per file.
class OneDeclarationPerModelFile extends AnalysisRule {
  OneDeclarationPerModelFile() : super(name: 'one_declaration_per_model_file', description: _desc);

  static const _desc = 'One top-level class, enum or extension per model file.';

  static const LintCode code = LintCode(
    'one_declaration_per_model_file',
    '[NEON] {0} is a further top-level declaration of this model file; move it into its own file {1}.dart.',
    correctionMessage: 'Declare one class, enum or extension per model file, the file named after it (an enum in '
        'lib/model/enums/<scope>/); fold an extension into the class or enum it extends.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addCompilationUnit(this, _OneDeclarationVisitor(this, RuleLayout.of(context)));
  }
}

/// The name token of a type declaration, or null for a function or variable.
Token? _typeDeclarationName(CompilationUnitMember member) => switch (member) {
      ClassDeclaration() => member.namePart.typeName,
      EnumDeclaration() => member.namePart.typeName,
      MixinDeclaration() => member.name,
      ExtensionTypeDeclaration() => member.primaryConstructor.typeName,
      ExtensionDeclaration() => member.name ?? member.extensionKeyword,
      TypeAlias() => member.name,
      _ => null,
    };

class _OneDeclarationVisitor extends SimpleAstVisitor<void> {
  _OneDeclarationVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    final path = unitPath(node);
    if (!layout.isAppSource(path) || !layout.isIn(path, LayoutRole.model)) return;
    var seen = 0;
    for (final member in node.declarations) {
      final name = _typeDeclarationName(member);
      if (name == null) continue;
      seen++;
      if (seen == 1) continue;
      final label = name.type == Keyword.EXTENSION ? 'an unnamed extension' : name.lexeme;
      final bare = name.lexeme.startsWith('_') ? name.lexeme.substring(1) : name.lexeme;
      rule.reportAtToken(name, arguments: [label, snakeCase(bare)]);
    }
  }
}

/// A class that serializes lives in the model role, and the model role holds
/// models only.
///
/// Outside the model role: a class with a `fromJson` constructor or static
/// method, a `toJson` method or `@JsonSerializable` (`vernak_card_models.dart`
/// in a cubit folder, `pricing_tier_models.dart` in the kit).
///
/// Inside it: UI. A widget or `State` class, a `*Dimens` class, an import of
/// `package:flutter/material.dart` / `widgets.dart` / `cupertino.dart`
/// (`Color` comes from `dart:ui`) and an import of the UI roles (pages,
/// features, the widget kit).
class ModelsOnlyInModel extends AnalysisRule {
  ModelsOnlyInModel() : super(name: 'models_only_in_model', description: _desc);

  static const _desc = 'Models live only in lib/model/, and lib/model/ holds nothing but models.';

  static const LintCode code = LintCode(
    'models_only_in_model',
    '[NEON] {0}; models live only in the model role ({1}) and it holds nothing but models.',
    correctionMessage: 'Move a serializing class into lib/model/ (one declaration per file); move widgets, dimens '
        'and other UI out of lib/model/ to the piece that draws it; take Color from dart:ui.',
    severity: DiagnosticSeverity.WARNING,
  );

  /// Flutter libraries a model never imports (UI). `dart:ui` and
  /// `package:flutter/foundation.dart` stay.
  static const uiLibraries = {
    'package:flutter/material.dart',
    'package:flutter/widgets.dart',
    'package:flutter/cupertino.dart',
  };

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addCompilationUnit(this, _ModelsOnlyVisitor(this, RuleLayout.of(context)));
  }
}

/// The members of [node] (none for a class without a body, `class X;`).
List<ClassMember> classMembers(ClassDeclaration node) {
  final body = node.body;
  return body is BlockClassBody ? body.members : const [];
}

/// Whether [node] has a `fromJson` constructor or static method, or a
/// `toJson` method.
bool hasJsonMembers(ClassDeclaration node) => classMembers(node).any(
      (member) => switch (member) {
        ConstructorDeclaration(:final name?) => name.lexeme == 'fromJson',
        MethodDeclaration() => member.name.lexeme == 'toJson' || member.name.lexeme == 'fromJson',
        _ => false,
      },
    );

/// Whether [node] is annotated `@JsonSerializable(...)`.
bool hasJsonSerializable(AnnotatedNode node) => node.metadata.any((annotation) {
      final name = annotation.name.name;
      return name == 'JsonSerializable' || name.endsWith('.JsonSerializable');
    });

/// A widget, a `State` or a `*Labels` object (the texts a kit widget takes):
/// never a model, even in a `*_models.dart` file.
bool _isWidgetOrLabels(ClassDeclaration node) {
  final type = node.declaredFragment?.element.thisType;
  return node.namePart.typeName.lexeme.endsWith('Labels') ||
      isSubtypeOf(type, 'Widget', package: 'flutter') ||
      isSubtypeOf(type, 'State', package: 'flutter');
}

class _ModelsOnlyVisitor extends SimpleAstVisitor<void> {
  _ModelsOnlyVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    final path = unitPath(node);
    if (!layout.isAppSource(path)) return;
    final model = layout.describe(LayoutRole.model);
    if (!layout.isIn(path, LayoutRole.model)) {
      final modelFile = _stem(path).endsWith('_model') || _stem(path).endsWith('_models');
      for (final declaration in node.declarations.whereType<ClassDeclaration>()) {
        final name = declaration.namePart.typeName;
        if (hasJsonMembers(declaration) || hasJsonSerializable(declaration)) {
          rule.reportAtToken(name, arguments: ['${name.lexeme} serializes outside the model role', model]);
        } else if (modelFile && !_isWidgetOrLabels(declaration)) {
          rule.reportAtToken(name, arguments: ['the model ${name.lexeme} is declared outside the model role', model]);
        }
      }
      return;
    }
    for (final directive in node.directives.whereType<ImportDirective>()) {
      final uri = directive.uri.stringValue ?? '';
      final target = importedPath(directive) ?? '';
      if (ModelsOnlyInModel.uiLibraries.contains(uri)) {
        rule.reportAtNode(directive.uri, arguments: ['a model imports `$uri` (UI)', model]);
      } else if (target.isNotEmpty && layout.isUi(target)) {
        rule.reportAtNode(directive.uri, arguments: ['a model imports the UI file `$uri`', model]);
      }
    }
    for (final declaration in node.declarations.whereType<ClassDeclaration>()) {
      final name = declaration.namePart.typeName;
      final type = declaration.declaredFragment?.element.thisType;
      if (isSubtypeOf(type, 'Widget', package: 'flutter') || isSubtypeOf(type, 'State', package: 'flutter')) {
        rule.reportAtToken(name, arguments: ['the widget ${name.lexeme} is in the model role', model]);
      } else if (name.lexeme.endsWith('Dimens')) {
        rule.reportAtToken(name, arguments: ['the dimens class ${name.lexeme} is in the model role', model]);
      }
    }
  }
}

/// A model file holds data, no helper functions: a top-level function (or
/// top-level getter / setter) in the model role is a finding. Parsing goes
/// through json_serializable and its converters, a derived value is a getter
/// of the model, anything else is a helper of `lib/utils/` or the cubit.
class NoLogicInModels extends AnalysisRule {
  NoLogicInModels() : super(name: 'no_logic_in_models', description: _desc);

  static const _desc = 'No top-level helper functions in model files.';

  static const LintCode code = LintCode(
    'no_logic_in_models',
    '[NEON] top-level function {0} in a model file; models hold data, no helper functions.',
    correctionMessage: 'Parse through json_serializable (@JsonKey, the converters of '
        'package:neon_flutter_utils/json.dart), make a derived value a getter or named constructor of the model, '
        'or move the helper to lib/utils/ or into the cubit.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addCompilationUnit(this, _NoLogicVisitor(this, RuleLayout.of(context)));
  }
}

class _NoLogicVisitor extends SimpleAstVisitor<void> {
  _NoLogicVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    final path = unitPath(node);
    if (!layout.isAppSource(path) || !layout.isIn(path, LayoutRole.model)) return;
    for (final function in node.declarations.whereType<FunctionDeclaration>()) {
      rule.reportAtToken(function.name, arguments: [function.name.lexeme]);
    }
  }
}
