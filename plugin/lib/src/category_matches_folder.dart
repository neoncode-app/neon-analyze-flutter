import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/file_system/file_system.dart';

import 'package:neon_lints/src/layering_rules.dart' show GlobalWidgetHasCategory;
import 'package:neon_lints/src/piece_rules.dart';
import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/layer_folders.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// A widget's folder says its layer (NCC0000058, see `layer_folders.dart`):
/// the `{@category}` of a public widget in the kit (layout role
/// `global_widgets`) or in a `widgets/` folder of a page or feature (roles
/// `pages`, `features`) matches the layer folder it sits in.
///
/// Where the layer folder goes, below an ANCHOR:
///
/// * a part of a piece (a file below a subfolder of `x/` holding `x/x.dart`):
///   `x/widgets/<layer>/`, e.g.
///   `lib/pages/vernak/vernak_company_page/widgets/patterns/company_users_block.dart`;
/// * a kit piece: `lib/global_widgets/<owner>/<layer>/`, e.g.
///   `lib/global_widgets/global/components/app_switch/app_switch.dart`; the
///   internals of a kit get theirs below its `src/`;
/// * any other widget below a `widgets/` folder of a page or feature (a
///   piece shared by several pages of one app): `widgets/<layer>/`.
///
/// The innermost layer-named folder between the anchor and the file counts,
/// so a grouping folder may stand on either side of it
/// (`global/stats/components/app_stat_tile/` or `global/components/stats/...`).
/// A `<name>_skeleton.dart` beside its widget moves with that widget and is
/// not placed on its own. A part of a page without a `{@category}` is
/// reported here; in the kit and the features `global_widget_has_category`
/// owns that.
class CategoryMatchesFolder extends AnalysisRule {
  CategoryMatchesFolder() : super(name: 'category_matches_folder', description: _desc);

  static const _desc = "A widget's folder says its layer: its {@category} matches the layer folder it sits in.";

  static const LintCode code = LintCode(
    'category_matches_folder',
    '[NEON] the folder of `{0}` does not say its layer: {1}.',
    correctionMessage: 'Put the widget in the folder of its layer: Component components/, Layout layouts/, '
        'Behavior behaviors/, Pattern patterns/, Template templates/, Skeleton skeletons/, Feature features/, '
        'any *Dialog or *Sheet dialogs/; under lib/global_widgets/<owner>/ and in widgets/ of a page or feature.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addClassDeclaration(
      this,
      _Visitor(this, RuleLayout.of(context), context.definingUnit.file.provider),
    );
  }
}

String _dirOf(String path) => path.substring(0, path.lastIndexOf('/'));

String _baseName(String path) => path.substring(path.lastIndexOf('/') + 1);

/// Where the layer folder of a file goes.
final class _Anchor {
  const _Anchor(this.path, {this.addWidgets = false});

  /// Absolute folder the layer folder goes directly into.
  final String path;

  /// The anchor is a piece's folder whose part is not in its `widgets/` yet:
  /// the suggestion puts `widgets/<layer>/` below it.
  final bool addWidgets;
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.layout, this.provider);

  final AnalysisRule rule;

  final RuleLayout layout;

  final ResourceProvider provider;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final name = node.name.lexeme;
    if (name.startsWith('_')) return;
    final path = unitPath(node);
    if (!layout.isAppSource(path) || layout.isIn(path, LayoutRole.catalogPreviews)) return;
    final inKit = layout.isIn(path, LayoutRole.globalWidgets);
    final inFeatures = layout.isIn(path, LayoutRole.features);
    final inPages = layout.isIn(path, LayoutRole.pages);
    if (!inKit && !inFeatures && !inPages) return;
    final element = node.declaredFragment?.element;
    if (element == null || !isSubtypeOf(element.thisType, 'Widget', package: 'flutter')) return;
    if (_besideItsWidget(name, path)) return;
    final anchor = _anchorOf(path, inKit: inKit);
    if (anchor == null) return;

    final category = categoryOf(element);
    final expected = expectedLayerFolder(name, GlobalWidgetHasCategory.tiers.contains(category) ? category : null);
    if (expected == null) {
      // The kit and the features have global_widget_has_category for this.
      if (inKit || inFeatures || path.contains('/src/')) return;
      rule.reportAtToken(
        node.name,
        arguments: [
          name,
          'it names no layer; end its doc comment with `/// {@category X}` '
              '(${GlobalWidgetHasCategory.tiers.join(', ')}) and put it in that layer\'s folder',
        ],
      );
      return;
    }

    final segments = _dirOf(path).length > anchor.path.length
        ? _dirOf(path).substring(anchor.path.length + 1).split('/')
        : <String>[];
    var current = -1;
    // A part outside its piece's widgets/ is in no layer folder yet.
    for (var i = segments.length - 1; i >= 0 && !anchor.addWidgets; i--) {
      if (layerFolderNames.contains(segments[i])) {
        current = i;
        break;
      }
    }
    if (current >= 0 && segments[current] == expected) return;

    final where = current >= 0 ? 'sits in `${segments[current]}/`' : 'sits in no layer folder';
    final String suggested;
    if (current >= 0) {
      segments[current] = expected;
      suggested = '${anchor.path}/${segments.join('/')}/${_baseName(path)}';
    } else {
      final rest = path.substring(anchor.path.length + 1);
      suggested = '${anchor.path}/${anchor.addWidgets ? 'widgets/' : ''}$expected/$rest';
    }
    final what = name.endsWith('Skeleton')
        ? 'a skeleton of its own'
        : name.endsWith('Dialog') || name.endsWith('Sheet')
            ? 'a dialog'
            : 'a $category';
    rule.reportAtToken(
      node.name,
      arguments: [name, 'it is $what but $where; move it to `${layout.relative(suggested) ?? suggested}`'],
    );
  }

  /// A `<Name>Skeleton` in `<name>_skeleton.dart`, or next to `<name>.dart`:
  /// the placeholder of the widget beside it, placed together with it.
  bool _besideItsWidget(String name, String path) {
    final dir = _dirOf(path);
    final file = _baseName(path);
    if (file.endsWith('_skeleton.dart')) {
      final stem = file.substring(0, file.length - '_skeleton.dart'.length);
      if (stem == _baseName(dir) || provider.getFile('$dir/$stem.dart').exists) return true;
    }
    if (!name.endsWith('Skeleton') || name == 'Skeleton') return false;
    final widget = snakeCase(name.substring(0, name.length - 'Skeleton'.length));
    return provider.getFile('$dir/$widget.dart').exists;
  }

  /// The folder the layer folder of [path] goes into, or null when the file
  /// is not placed by layer (a page, a feature piece, the kit root).
  _Anchor? _anchorOf(String path, {required bool inKit}) {
    final piece = pieceFolderAbove(path, layout, provider);
    if (piece != null) {
      final widgets = '$piece/widgets';
      if (path.startsWith('$widgets/')) return _Anchor(widgets);
      return _Anchor(piece, addWidgets: true);
    }
    if (inKit) {
      for (final folder in layout.absoluteFolders(LayoutRole.globalWidgets)) {
        if (!path.startsWith(folder)) continue;
        final rest = path.substring(folder.length);
        final slash = rest.indexOf('/');
        if (slash < 0) return null;
        final owner = '$folder${rest.substring(0, slash)}';
        final src = path.indexOf('/src/', owner.length);
        return _Anchor(src >= 0 ? path.substring(0, src + '/src'.length) : owner);
      }
      return null;
    }
    for (final role in const [LayoutRole.pages, LayoutRole.features]) {
      for (final folder in layout.absoluteFolders(role)) {
        if (!path.startsWith(folder)) continue;
        final rest = '/${path.substring(folder.length)}';
        final widgets = rest.indexOf('/widgets/');
        if (widgets < 0) continue;
        return _Anchor('$folder${rest.substring(1, widgets + '/widgets'.length)}');
      }
    }
    return null;
  }
}
