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

/// The methods of the app's dialog helper `Utils`: the Future-returning
/// `showCustomModalBottomSheet` and its void entry point for dialog openers,
/// `openModalBottomSheet` (NCC0000062).
const dialogHelperMethods = {'showCustomModalBottomSheet', 'openModalBottomSheet'};

/// `Utils.showCustomModalBottomSheet(...)` or `Utils.openModalBottomSheet(...)`,
/// the one dialog helper.
bool isDialogHelperCall(MethodInvocation node) {
  if (!dialogHelperMethods.contains(node.methodName.name)) return false;
  final owner = node.methodName.element?.enclosingElement;
  return owner is InterfaceElement && owner.name == 'Utils';
}

/// Whether [name] (a function or method name, private or not) names a dialog
/// opener by convention: it starts with `show` (`showCouponEditor`,
/// `_showStep`, a static `show`).
bool isOpenerName(String name) => (name.startsWith('_') ? name.substring(1) : name).startsWith('show');

/// The `package:<name>/` prefix of the library [node] is in, or null for a
/// file outside a package.
String? packagePrefixOf(AstNode node) {
  final unit = node.root;
  if (unit is! CompilationUnit) return null;
  final uri = unit.declaredFragment?.source.uri.toString() ?? '';
  if (!uri.startsWith('package:')) return null;
  final slash = uri.indexOf('/');
  return slash < 0 ? null : uri.substring(0, slash + 1);
}

/// Whether [type] is Flutter's `BuildContext`.
bool isBuildContext(DartType? type) =>
    type is InterfaceType && type.element.name == 'BuildContext' && isFromPackage(type.element, 'flutter');

/// Whether [invocation] passes a `BuildContext`, positional or named: a
/// dialog is opened on a context, so a `show*` call without one (a system
/// notification, `FlutterLocalNotificationsPlugin.show`) opens none.
bool passesBuildContext(MethodInvocation invocation) => invocation.argumentList.arguments.any(
  (argument) => isBuildContext((argument is NamedExpression ? argument.expression : argument).staticType),
);

/// Whether [invocation] calls an app dialog opener that returns a Future: a
/// `show*` function or method declared in the same package as [invocation]
/// whose static type is a Future and which gets a `BuildContext`
/// (`showCouponEditor(context, event)`, `EditRolesSheet.show(context)`).
/// Flutter's own `showDialog` is not one.
bool callsFutureOpener(MethodInvocation invocation) {
  if (!isOpenerName(invocation.methodName.name) || !passesBuildContext(invocation)) return false;
  final type = invocation.staticType;
  if (type == null || !type.isDartAsyncFuture) return false;
  final declared = invocation.methodName.element?.library?.uri.toString();
  final package = packagePrefixOf(invocation);
  return declared != null && package != null && declared.startsWith(package);
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

/// Whether [expression] always has the same value: a literal, a `const`
/// construction, or a read of a `const` / `static final` / top-level `final`
/// variable.
bool isConstantValue(Expression expression) {
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
