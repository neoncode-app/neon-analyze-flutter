import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Shared helpers for the neoncode architecture rules.

/// Path of the compilation unit [node] belongs to, normalised to `/`.
String unitPath(AstNode node) {
  final unit = node.root;
  if (unit is! CompilationUnit) return '';
  return (unit.declaredFragment?.source.fullName ?? '').replaceAll(r'\', '/');
}

/// App code: a file under `lib/` that is not generated.
bool isAppSource(String path) => path.contains('/lib/') && !path.endsWith('.g.dart') && !path.endsWith('.freezed.dart');

/// Whether [path] is under `lib/<relative>` (a folder ends with `/`).
bool isUnderLib(String path, String relative) =>
    relative.endsWith('/') ? path.contains('/lib/$relative') : path.endsWith('/lib/$relative');

/// Whether [element] is declared in [package].
bool isFromPackage(Element? element, String package) =>
    element?.library?.uri.toString().startsWith('package:$package/') ?? false;

/// Whether [type] is, or extends / implements, the class [name] of [package].
/// With a null [package] any library matches (app classes such as BaseCubit).
bool isSubtypeOf(DartType? type, String name, {String? package}) {
  if (type is! InterfaceType) return false;
  bool matches(InterfaceType candidate) =>
      candidate.element.name == name && (package == null || isFromPackage(candidate.element, package));
  return matches(type) || type.allSupertypes.any(matches);
}

/// Whether [type] is a bloc or cubit (`BlocBase` of package:bloc).
bool isBloc(DartType? type) => isSubtypeOf(type, 'BlocBase', package: 'bloc');

/// The class declaration enclosing [node], if any.
ClassDeclaration? enclosingClass(AstNode node) => node.thisOrAncestorOfType<ClassDeclaration>();

/// The supertype instance named [name] of the class declared by
/// [declaration] (e.g. `BaseCubit<S>`), if it has one.
InterfaceType? supertypeNamed(ClassDeclaration declaration, String name) {
  final element = declaration.declaredFragment?.element;
  if (element == null) return null;
  for (final type in [element.thisType, ...element.allSupertypes]) {
    if (type.element.name == name) return type;
  }
  return null;
}

/// Folders of UI code (pages, features, global widgets).
const uiFolders = ['pages/', 'features/', 'global_widgets/'];

bool isUiSource(String path) => isAppSource(path) && uiFolders.any((folder) => isUnderLib(path, folder));

/// `context.read<X>()`, `context.watch<X>()`, `context.select<X, R>(...)` or
/// `BlocProvider.of<X>(context)`.
bool isProviderRead(MethodInvocation node) {
  final method = node.methodName.element;
  if (method is! MethodElement) return false;
  final owner = method.enclosingElement;
  if (owner is ExtensionElement) {
    return const {'ReadContext', 'WatchContext', 'SelectContext'}.contains(owner.name) &&
        isFromPackage(owner, 'provider');
  }
  return method.name == 'of' && owner?.name == 'BlocProvider' && isFromPackage(owner, 'flutter_bloc');
}

/// `Utils.showCustomModalBottomSheet(...)`, the one dialog helper.
bool isDialogHelperCall(MethodInvocation node) {
  if (node.methodName.name != 'showCustomModalBottomSheet') return false;
  final owner = node.methodName.element?.enclosingElement;
  return owner is InterfaceElement && owner.name == 'Utils';
}

/// Whether [function] is the `listener:` callback of a
/// `BlocPresentationListener` (package:bloc_presentation).
bool isPresentationListener(FunctionExpression function) {
  final argument = function.parent;
  if (argument is! NamedExpression || argument.name.label.name != 'listener') return false;
  final creation = argument.parent?.parent;
  if (creation is! InstanceCreationExpression) return false;
  final widget = creation.constructorName.element?.enclosingElement;
  return widget?.name == 'BlocPresentationListener' && isFromPackage(widget, 'bloc_presentation');
}

/// The innermost function (function expression, function or method
/// declaration) enclosing [node].
AstNode? enclosingFunction(AstNode node) {
  for (AstNode? current = node.parent; current != null; current = current.parent) {
    if (current is FunctionExpression || current is MethodDeclaration) return current;
    if (current is FunctionDeclaration) return current;
  }
  return null;
}

/// The `{@category X}` of [element]'s doc comment, if any.
String? categoryOf(Element? element) {
  final doc = element?.documentationComment;
  if (doc == null) return null;
  final matches = RegExp(r'\{@category\s+(\w+)\}').allMatches(doc).toList();
  return matches.isEmpty ? null : matches.last.group(1);
}

/// Absolute path of the library an import directive resolves to.
String? importedPath(ImportDirective node) =>
    node.libraryImport?.importedLibrary?.firstFragment.source.fullName.replaceAll(r'\', '/');
