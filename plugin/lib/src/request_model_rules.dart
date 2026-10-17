import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/support/ast_support.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

// Request models (NCC0000067, decided by Filip 2026-10-16):
//
//   lib/model/request_models/_base/<project>_request.dart   one base per tenant,
//                                                           the only place that
//                                                           sets `project`
//   lib/model/request_models/<project>/<domain>/<name>_request.dart
//
// A request in `<project>/` extends that project's base; `common/` (the
// session's own tenant) extends plain NeoRequest. TenantScopedRequest, whose
// caller chooses the tenant, is allowed in every folder. The tenant never goes
// into extraHeaders.

const _requestModels = '/request_models/';

const _baseFolder = '_base';

const _tenantScopedBase = 'tenant_scoped_request.dart';

/// The folder of [path] under `request_models/`: `null` outside it, `''` for a
/// file directly in it (no project folder yet).
String? _requestFolder(String path) {
  final at = path.indexOf(_requestModels);
  if (at < 0) return null;
  final rest = path.substring(at + _requestModels.length);
  final slash = rest.indexOf('/');
  return slash < 0 ? '' : rest.substring(0, slash);
}

String _sourceOf(Element element) => (element.library?.firstFragment.source.fullName ?? '').replaceAll(r'\', '/');

/// Whether [element] is neonapi's `NeoRequest` or a class built on it.
bool isNeoRequest(InterfaceElement element) => [element.thisType, ...element.allSupertypes].any(
      (type) => type.element.name == 'NeoRequest' && _sourceOf(type.element).contains('/neonapi'),
    );

/// A request lives in `request_models/<project>/<domain>/`, extends its
/// project's base from `request_models/_base/` and never sets `project` itself.
class RequestExtendsProjectBase extends AnalysisRule {
  RequestExtendsProjectBase() : super(name: 'request_extends_project_base', description: _desc);

  static const _desc =
      'A request in request_models/<project>/ extends that project\'s base; only the bases set project.';

  static const LintCode code = LintCode(
    'request_extends_project_base',
    '[NEON] request {0} {1}.',
    correctionMessage: 'Put the request in lib/model/request_models/<project>/<domain>/<name>_request.dart and extend '
        'the base of that project from request_models/_base/ (VernakRequest, NeoncodeRequest, DoorDropRequest, '
        'QuestRequest; common/ extends NeoRequest; TenantScopedRequest when the caller chooses the tenant). '
        'Only the bases override `project`.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addClassDeclaration(this, _BaseVisitor(this, RuleLayout.of(context)));
  }
}

class _BaseVisitor extends SimpleAstVisitor<void> {
  _BaseVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final path = unitPath(node);
    if (!layout.isAppSource(path) || !layout.isIn(path, LayoutRole.model)) return;
    final folder = _requestFolder(path);
    if (folder == null || folder == _baseFolder) return;
    final element = node.declaredFragment?.element;
    if (element == null || !isNeoRequest(element)) return;
    final name = node.namePart.typeName;
    if (folder.isEmpty) {
      rule.reportAtToken(name, arguments: [name.lexeme, 'is not in request_models/<project>/<domain>/']);
    } else if (!_extendsBaseOf(element, folder)) {
      final expected = folder == 'common' ? 'NeoRequest' : 'the base in request_models/_base/${folder}_request.dart';
      rule.reportAtToken(name, arguments: [name.lexeme, 'in request_models/$folder/ does not extend $expected']);
    }
    final body = node.body;
    if (body is! BlockClassBody) return;
    for (final member in body.members) {
      final token = switch (member) {
        MethodDeclaration(isGetter: true) when member.name.lexeme == 'project' => member.name,
        FieldDeclaration() => member.fields.variables.where((v) => v.name.lexeme == 'project').firstOrNull?.name,
        _ => null,
      };
      if (token == null) continue;
      rule.reportAtToken(token, arguments: [name.lexeme, 'sets `project`; only the bases in request_models/_base/ do']);
    }
  }

  /// Whether [element] extends the base of [folder], or the tenant-scoped base.
  /// `common/` requests extend no base at all.
  bool _extendsBaseOf(InterfaceElement element, String folder) {
    final bases = [
      for (final type in element.allSupertypes)
        if (_requestFolder(_sourceOf(type.element)) == _baseFolder) _sourceOf(type.element),
    ];
    if (bases.any((path) => path.endsWith('/$_baseFolder/$_tenantScopedBase'))) return true;
    if (folder == 'common') return bases.isEmpty;
    return bases.any((path) => path.endsWith('/$_baseFolder/${folder}_request.dart'));
  }
}

/// No `extraHeaders` override puts the tenant (`x-project`) in a header; the
/// request declares `project` through its base (neonapi asserts on it too).
class NoTenantInExtraHeaders extends AnalysisRule {
  NoTenantInExtraHeaders() : super(name: 'no_tenant_in_extra_headers', description: _desc);

  static const _desc = 'The tenant is never set in extraHeaders; the request declares project through its base.';

  static const LintCode code = LintCode(
    'no_tenant_in_extra_headers',
    '[NEON] {0} sets x-project in extraHeaders.',
    correctionMessage: 'Remove the x-project header and extend the project base from request_models/_base/ '
        '(TenantScopedRequest when the caller chooses the tenant).',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addMethodDeclaration(this, _HeadersVisitor(this, RuleLayout.of(context)));
  }
}

class _HeadersVisitor extends SimpleAstVisitor<void> {
  _HeadersVisitor(this.rule, this.layout);

  final AnalysisRule rule;

  final RuleLayout layout;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (!node.isGetter || node.name.lexeme != 'extraHeaders') return;
    if (!layout.isAppSource(unitPath(node))) return;
    final owner = node.parent?.parent;
    if (owner is! ClassDeclaration) return;
    final finder = _TenantKeyFinder();
    node.body.accept(finder);
    if (!finder.found) return;
    rule.reportAtToken(node.name, arguments: [owner.namePart.typeName.lexeme]);
  }
}

/// Finds an `'x-project'` string or a reference to `NeoRequest.projectHeader`.
class _TenantKeyFinder extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (node.value.toLowerCase() == 'x-project') found = true;
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == 'projectHeader') found = true;
    super.visitSimpleIdentifier(node);
  }
}
