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
| `use_context_getters` | lint (neoncode) | `context.read/watch/select` and `BlocProvider.of` only in `lib/flavors/<f>/<f>_providers.dart` |
| `cubit_created_in_provider` | lint (neoncode) | a bloc / cubit is constructed only in a provider's `create:` callback |
| `provider_in_router` | lint (neoncode) | `BlocProvider` / `MultiBlocProvider` only in `lib/flavors/**` and `lib/utils/utils.dart` |
| `no_cubit_call_in_lifecycle` | lint (neoncode) | no cubit method call directly in `initState`, `didChangeDependencies`, `build` |
| `no_provider_value` | lint (neoncode) | no `BlocProvider.value` of a cubit held in a `State` field |
| `cancel_subscriptions_in_close` | lint (neoncode) | `stream.listen` in a cubit stored in a field and cancelled in `close()` |
| `alert_only_in_cubit` | lint (neoncode) | no `AlertCubit` in `lib/pages`, `lib/features`, `lib/global_widgets` |
| `state_is_sealed` | lint (neoncode) | the state of a `BaseCubit<S>` is `sealed` (except `lib/bloc/<app>/app_wide/`) |
| `no_status_enum_state` | lint (neoncode) | no `XStatus` enum field in a state class under `lib/bloc` |

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

## Check runner (`checker/`)

`neon_check` runs every repo-level check of an app in a fixed order, stops at
the first failing step and prints failures only (`file:line rule: what to do`);
a green run prints one summary line. Each app has a `neon_check.yaml` at its
root (languages, paths, suites) and a `tool/check.sh` wrapper that runs
`checker/bin/neon_check.dart`. Steps (`tool/check.sh --list`):

| # | Step | Does | Auto-fix |
| --- | --- | --- | --- |
| 1 | `format` | `dart format --line-length 120` | yes |
| 2 | `fix` | `dart fix --apply` (core fixes; plugin fixes are IDE-only) | yes |
| 3 | `analyze` | `dart analyze` on the root (`--all`) or on file paths, then the ratchet | no |
| 4 | `ignores` | no `// ignore:` for a `[NEON]` rule | no |
| 5 | `translations_parity` | same keys in every language file | no |
| 6 | `translations_dashes` | no `—` `–` `−` `--` in values | no |
| 7 | `translations_missing` | every literal `tr('key')` exists | no |
| 8 | `translations_unused` | keys no code uses (`--all` only) | `--prune-translations` |
| 9 | `translations_order` | keys in the primary file's order | yes |
| 10 | `assets` | registry paths exist; unused asset files (`--all`) | no |
| 11 | `catalog_index` | widget catalog index regenerated | yes |
| 12 | `catalog_previews` | every widget in `preview_required` has a preview | no |
| 13 | `providers` | context getters match cubits provided in the router / shell | no |
| 14 | `page_help` | every configured page has `onHelp` and its help keys | no |
| 15 | `generated` | `*.g.dart` match their sources (build_runner) | yes |
| 16 | `tests` | `flutter test`, suites selected by the changed files | no |

**Scope.** Default `--changed`: files changed against the branch base
(`branch.<name>.neonBase`, else `default_base`), plus uncommitted and
untracked files. `--all` checks everything (CI), `--staged` the files staged
for commit, `--files a b` an explicit list. `--ci` never changes a file: an
auto-fix step that would change something fails instead.

**Ratchet.** Every finding except compile errors, tool crashes and failing
tests is counted per rule and file against `tool/lint_baseline.json`
(`baseline` in the config). More than the baseline fails; fewer lowers the
baseline automatically, so a fixed violation cannot come back. The baseline is
written by `--update-baseline` (do this when a new rule lands) and never raised
by hand.

**Migrations.** `--zero <rule>[,<rule>]` demands no finding at all for those
rules, baseline or not (whole project). `--rule <rule>` lists every finding of
one rule with `file:line` and exits 0. `--max-failures <n>` caps the printed
failures (for hooks). `--step <name>` runs one step alone.

**Test suites.** `tests.default_suite` always runs and owns every test outside
the other suites' folders; a changed source matching a suite's `sources`
globs (or a changed test in its folder) adds that suite; a `shared` glob runs
every suite; `--all` runs all suites plus `integration_command`.

Run the runner's own tests with `cd checker && dart test`.

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
