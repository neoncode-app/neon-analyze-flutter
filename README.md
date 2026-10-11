# neon-analyze-flutter

Shared analyzer setup for the Neon Code Flutter apps (vernakapp, neoncode,
baseapp). Two parts in one repo:

- **`lib/analysis_options.yaml`**: the lint ruleset, a fork of very_good_analysis
  (VGV 10.2.0, frozen in `lib/analysis_options.10.2.0.yaml`) plus our curation.
- **`plugin/`**: `neon_lints`, a native analyzer plugin (built on Dart's
  first-party `analysis_server_plugin`) with our own rules, reported with a
  `[NEON]` prefix.

## Running the rules

Only **`dart analyze`** runs the plugin, from the app's package root or on
explicit file paths:

```bash
dart analyze                 # whole app, plugin rules included
dart analyze lib/a.dart      # one file, plugin rules included
dart analyze lib             # a DIRECTORY below the root: plugin rules are SKIPPED
```

Every `[NEON]` rule reports a WARNING, so a violation makes `dart analyze` exit
with code 2 (3 when a rule is raised to `error`). After changing the plugin
source, clear its compiled copy so the analysis server rebuilds it:
`rm -rf ~/.dartServer/.plugin_manager` (or only the folder whose
`pubspec.yaml` points at this plugin path).

## How the apps use it

Added to each app as a git submodule at `neon-analyze-flutter/`, then in the
app's `analysis_options.yaml`:

```yaml
include: package:neon_analysis/analysis_options.yaml
plugins:
  neon_lints:
    path: neon-analyze-flutter/plugin
    diagnostics:          # optional, see below
      use_kit_widgets: true
```

## Enabling rules per app

The plugin registers two kinds of rules (verified on Dart 3.12.2):

| Kind | Registered with | Default | Used for |
| --- | --- | --- | --- |
| warning rule | `registry.registerWarningRule` | ON in every app | generic rules every app follows |
| lint rule | `registry.registerLintRule` | OFF until the app enables it | rules that encode one app's architecture |

An app configures them under `plugins: neon_lints: diagnostics:` in its own
`analysis_options.yaml`:

| Value | Effect |
| --- | --- |
| `true` | enables a lint rule at the rule's own severity |
| `false` | disables any rule, warning rules included |
| `error` / `warning` / `info` | enables the rule AND sets its severity |
| `ignore` | does NOT disable the rule; use `false` |

`analyzer: errors:` does not apply to plugin rules. The `plugins` section is
inherited through `include:`, and the app's own `diagnostics` keys are merged
over the included ones, so a shared preset file holding only a `diagnostics`
map can switch a whole rule set on with one include.

Suppressing one occurrence: `// ignore: neon_lints/<rule>`.

## Rules

| Rule | Kind | What it enforces |
| --- | --- | --- |
| `avoid_bang` | warning | no null-assertion `!` |
| `extend_base_cubit` | warning | cubits extend `BaseCubit` |
| `no_widget_builder_method` | warning | no private `Widget _buildX()` methods |
| `no_raw_color` | warning | no `Color(0x..)` / `Colors.x` outside theme files |
| `no_raw_asset_path` | warning | no `'assets/...'` literals outside `AppAssets` |
| `no_tr_in_global_widget` | warning | no `tr()` under `lib/global_widgets/` |
| `use_kit_widgets` | lint (neoncode) | raw Flutter widgets and APIs the admin widget kit replaces; the message names the kit widget to use |
| `no_navigator` | lint (neoncode) | no `Navigator.*`; navigate with go_router (`context.pop` / `go` / `push`) |

### Banned-API rules (`use_kit_widgets`, `no_navigator`)

Both are driven by a table in their source file: one `BannedApi` row per
banned API, with its replacement and the owner files (paths relative to `lib/`)
that implement the replacement and may therefore still use the raw API. Adding
a ban is one row. Matching is type-resolved (element name plus declaring
package), so an app class that happens to be called `Switch` is not flagged
and an import prefix does not hide a banned API. A row flags constructing the
class, constructor tear-offs, static member access (`Icons.add`,
`Navigator.of`), calls of banned top-level functions (`showDialog`) and,
for whole packages, imports (`package:fl_chart`). Type annotations are never
flagged. A row can also give ownership to every file that declares a class
with a given `{@category ...}`, which is how any template may use `Scaffold`.
Only files under `lib/` are checked; generated files (`*.g.dart`,
`*.freezed.dart`) are skipped.

## Quick fixes

Plugin quick fixes are IDE-only. `dart fix --apply` does not apply them
("Nothing to fix!"), and `dart fix --code=<plugin rule>` rejects the code as
unknown (verified on Dart 3.12.2 with `analysis_server_plugin` 0.3.10). Bulk
mechanical migrations need a codemod script instead.

## Adding or changing rules

Use the **`neon-rule-author`** agent: it holds the plugin API, the rule
template and the submodule commit / pin-bump workflow. Every rule ships with
tests in `plugin/test/` (`analyzer_testing`): a violating case, a clean case,
and the allow-listed owner file. Run them with:

```bash
cd plugin && dart test
```

Tests resolve against small stub packages (`test/support/stub_packages.dart`),
so a rule that matches a Flutter, `intl` or `fl_chart` element needs that
element stubbed there.

For plain YAML lint on/off, edit the `linter: rules:` block in
`lib/analysis_options.yaml`.

## Updating the very_good_analysis base

`git fetch upstream && git merge upstream/main`, then point the `include:` in
`lib/analysis_options.yaml` at the newer `analysis_options.<version>.yaml`
(add that file from upstream).
