import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/file_system.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// One folder per piece (ESME rule `component_folder_with_skeleton`): every
/// component, layout, behavior, pattern, template, feature and page lives in
/// a folder named after its file, beside its dimens and its skeleton:
///
/// ```
/// app_switch/
///   app_switch.dart            AppSwitch
///   app_switch_dimens.dart     AppSwitchDimens
///   app_switch_skeleton.dart   AppSwitchSkeleton
///   <subfolders>/              the parts of the piece
/// ```
///
/// A PIECE is a public widget of the kit, the features or the pages that is
/// not a PART: a file below a subfolder of a piece's folder is a part of that
/// piece and has no folder of its own. The skeleton file of a piece is part
/// of it too.

/// Tiers that have no skeleton of their own: a behavior adds nothing to draw,
/// a layout and a template are rendered as they are around the skeletons of
/// their children, and a skeleton is the placeholder itself.
const _withoutSkeleton = {'Layout', 'Behavior', 'Template', 'Skeleton'};

/// Name suffixes of pieces that are never shown as a loading placeholder: a
/// dialog or a sheet opens over a page that is already loaded.
const _overlaySuffixes = ['Dialog', 'Sheet'];

/// `AppSwitch` -> `app_switch`, `AppHTMLView` -> `app_html_view`.
String snakeCase(String name) => name
    .replaceAllMapped(RegExp('([A-Z]+)([A-Z][a-z])'), (m) => '${m[1]}_${m[2]}')
    .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
    .toLowerCase();

String _dirOf(String path) => path.substring(0, path.lastIndexOf('/'));

String _baseName(String path) => path.substring(path.lastIndexOf('/') + 1);

String _stem(String path) {
  final name = _baseName(path);
  return name.endsWith('.dart') ? name.substring(0, name.length - '.dart'.length) : name;
}

/// A piece found in a class declaration.
final class _Piece {
  _Piece(this.name, this.path, this.category);

  /// Class name (`AppSwitch`).
  final String name;

  /// Absolute path of the file declaring it.
  final String path;

  /// Its `{@category}`, `Skeleton` for a `*Skeleton` class, or null.
  final String? category;

  /// The file name of the piece: its current one when that already spells
  /// the class (underscores aside, so `doordrop` names `DoorDrop`), otherwise
  /// the class in snake case.
  String get snake {
    final stem = _stem(path);
    return stem.replaceAll('_', '') == name.toLowerCase() ? stem : snakeCase(name);
  }

  /// Whether it already is the entry file of its own folder.
  bool get inOwnFolder => _stem(path) == snake && _baseName(_dirOf(path)) == snake;

  /// The folder it belongs in (absolute).
  String get folder => inOwnFolder ? _dirOf(path) : '${_dirOf(path)}/$snake';

  bool get needsSkeleton =>
      !_withoutSkeleton.contains(category) && !_overlaySuffixes.any((suffix) => name.endsWith(suffix));
}

/// The piece [node] declares, or null when it is no piece (private, not a
/// widget, outside the UI roles, a catalog preview, a part of another piece
/// or the skeleton of one).
_Piece? _pieceOf(ClassDeclaration node, RuleLayout layout, ResourceProvider provider) {
  final name = node.name.lexeme;
  if (name.startsWith('_')) return null;
  final path = unitPath(node);
  if (!isAppSource(path) || layout.isIn(path, LayoutRole.catalogPreviews)) return null;
  final isPage = layout.isIn(path, LayoutRole.pages);
  if (!isPage && !layout.isIn(path, LayoutRole.globalWidgets) && !layout.isIn(path, LayoutRole.features)) return null;
  final element = node.declaredFragment?.element;
  if (element == null || !isSubtypeOf(element.thisType, 'Widget', package: 'flutter')) return null;
  if (_isPartOrSkeleton(path, layout, provider)) return null;
  final category = name.endsWith('Skeleton') ? 'Skeleton' : categoryOf(element);
  return _Piece(name, path, category);
}

/// Whether [path] is the skeleton file of its folder's piece, or lies below a
/// subfolder of a piece's folder (a folder `x/` holding `x/x.dart`).
bool _isPartOrSkeleton(String path, RuleLayout layout, ResourceProvider provider) {
  final dir = _dirOf(path);
  if (_baseName(path) == '${_baseName(dir)}_skeleton.dart') return true;
  final lib = '${layout.root}/lib';
  for (var ancestor = _dirOf(dir); ancestor.length > lib.length; ancestor = _dirOf(ancestor)) {
    if (provider.getFile('$ancestor/${_baseName(ancestor)}.dart').exists) return true;
  }
  return false;
}

String _relative(RuleLayout layout, String path) => layout.relative(path) ?? path;

/// Every piece is the entry file of a folder named after it, and that folder
/// holds no second piece (parts go into subfolders).
class PieceInOwnFolder extends AnalysisRule {
  PieceInOwnFolder() : super(name: 'piece_in_own_folder', description: _desc);

  static const _desc = 'Every piece lives in its own folder, named after its file.';

  static const LintCode code = LintCode(
    'piece_in_own_folder',
    '[NEON] `{0}` is not in its own folder; move it to `{1}` (beside its dimens and skeleton). '
        'A part of a bigger piece goes into a subfolder of that piece\'s folder.',
    correctionMessage: 'Move the widget into its folder and keep one public entry file there.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addClassDeclaration(
      this,
      _FolderVisitor(this, RuleLayout.of(context), context.definingUnit.file.provider),
    );
  }
}

class _FolderVisitor extends SimpleAstVisitor<void> {
  _FolderVisitor(this.rule, this.layout, this.provider);

  final AnalysisRule rule;

  final RuleLayout layout;

  final ResourceProvider provider;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final piece = _pieceOf(node, layout, provider);
    if (piece == null || piece.inOwnFolder) return;
    rule.reportAtToken(node.name, arguments: [piece.name, _relative(layout, '${piece.folder}/${piece.snake}.dart')]);
  }
}

/// Every piece with a look of its own has `<name>_skeleton.dart` declaring
/// `<Name>Skeleton` in its folder; layouts, behaviors, templates, skeletons,
/// dialogs and sheets have none.
class PieceHasSkeleton extends AnalysisRule {
  PieceHasSkeleton() : super(name: 'piece_has_skeleton', description: _desc);

  static const _desc = 'Every piece with a look of its own has a skeleton in its folder.';

  static const LintCode code = LintCode(
    'piece_has_skeleton',
    '[NEON] `{0}` has no skeleton; add `{1}` declaring `{0}Skeleton`, built from the skeleton primitives '
        'and the same <Name>Dimens as the widget.',
    correctionMessage: 'Write the skeleton beside the widget; a page skeleton is composed from its pieces\' skeletons.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addClassDeclaration(
      this,
      _SkeletonVisitor(this, RuleLayout.of(context), context.definingUnit.file.provider),
    );
  }
}

class _SkeletonVisitor extends SimpleAstVisitor<void> {
  _SkeletonVisitor(this.rule, this.layout, this.provider);

  final AnalysisRule rule;

  final RuleLayout layout;

  final ResourceProvider provider;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final piece = _pieceOf(node, layout, provider);
    if (piece == null || !piece.needsSkeleton) return;
    final skeleton = '${piece.folder}/${piece.snake}_skeleton.dart';
    if (_declares(skeleton, '${piece.name}Skeleton')) return;
    rule.reportAtToken(node.name, arguments: [piece.name, _relative(layout, skeleton)]);
  }

  bool _declares(String path, String className) {
    final file = provider.getFile(path);
    if (!file.exists) return false;
    try {
      return RegExp('class\\s+$className\\b').hasMatch(file.readAsStringSync());
    } on FileSystemException {
      return false;
    }
  }
}
