/// A widget's folder says its layer (NCC0000058).
///
/// The layer of a widget is its `{@category}`, and every layer has one folder
/// name, the same everywhere: under each owner of the kit
/// (`lib/global_widgets/<owner>/`), in every `widgets/` folder of a page or a
/// feature, and in a kit's `src/` folder:
///
/// | `{@category}`                 | folder        |
/// | ----------------------------- | ------------- |
/// | Component                     | `components/` |
/// | Layout                        | `layouts/`    |
/// | Behavior                      | `behaviors/`  |
/// | Pattern                       | `patterns/`   |
/// | Template                      | `templates/`  |
/// | Skeleton (a skeleton piece)   | `skeletons/`  |
/// | Feature (a part or kit piece) | `features/`   |
/// | any `*Dialog` / `*Sheet`      | `dialogs/`    |
///
/// A `<name>_skeleton.dart` beside its widget is not placed on its own: it
/// moves with the widget it belongs to (`component_folder_with_skeleton`).
/// Only a skeleton that is a piece of its own (`SkeletonCard`,
/// `CardListSkeleton`) lives in `skeletons/`.
///
/// A feature piece lives in `lib/features/<product>/<feature>/` and is under
/// no layer folder; its parts (and the parts of a page) go into
/// `widgets/<layer>/`, a feature-level part (one that reads a cubit) into
/// `widgets/features/`.
library;

/// The folder of every `{@category}`.
const layerFolderOfCategory = {
  'Component': 'components',
  'Layout': 'layouts',
  'Behavior': 'behaviors',
  'Pattern': 'patterns',
  'Template': 'templates',
  'Skeleton': 'skeletons',
  'Feature': 'features',
};

/// The folder of every `*Dialog` and `*Sheet`, whatever its category.
const dialogsFolder = 'dialogs';

/// Every folder name that says a layer.
final layerFolderNames = {...layerFolderOfCategory.values, dialogsFolder};

/// The layer folder a class named [className] with [category] belongs in, or
/// `null` when the category is missing or no layer.
String? expectedLayerFolder(String className, String? category) {
  if (className.endsWith('Skeleton')) return layerFolderOfCategory['Skeleton'];
  if (className.endsWith('Dialog') || className.endsWith('Sheet')) return dialogsFolder;
  return layerFolderOfCategory[category];
}

/// [path] without its layer folders (`/components/`, `/patterns/`, ...): the
/// folder a piece had before NCC0000058 put the layer between the kit and
/// the piece. Table entries that name a piece by its folder compare with it.
String withoutLayerFolders(String path) {
  var result = path;
  for (final folder in layerFolderNames) {
    result = result.replaceAll('/$folder/', '/');
  }
  return result;
}
