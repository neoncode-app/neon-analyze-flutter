# neon-analyze-flutter

One tool that checks a Neon Code Flutter app after every change: formatting,
the analyzer and our own architecture rules, translations, assets, generated
code, the test gates, unit tests, coverage and the integration flows the change
affects. It is shared by every app (neoncode, vernakapp, doordropgo, ...) as a
git submodule at `neon-analyze-flutter/`; each app only says what it is in one
small file, `neon_check.yaml`.

## In short

```
read a file ──► brief: the rules and gates of that kind of file ──► write it right ──► neon-check ──► fix what is left
```

- **When the AI reads a `.dart` file** (or writes a new one) for the first time
  in a session for that folder and kind of file, it gets the BRIEF: what the
  file is (its layout roles), the rules of the enabled packs about it, the
  gates it must pass (cubit test, route test, integration flow, help dialog,
  catalog preview, translations) and the written ESME rules of its path. The
  code is written right instead of fixed after the checks fail.
- **After an AI edit of a `.dart` file** the `edit` trigger runs `dart analyze`
  on that file: a new problem goes back to the AI at once.
- **When the AI finishes a turn** (Claude Code Stop hook) the `stop` trigger
  checks every changed file: all static checks, the unit tests the change
  selects, coverage of changed cubit code and the integration flows it affects.
  The turn cannot end while it fails.
- **On `git commit`** the `commit` trigger checks the staged files (fast checks
  only, nothing is changed).
- **In CI and `/done`** the `ci` trigger checks the whole project, every test
  and every flow.

What each trigger runs is configuration (`triggers:`), not code.

## The parts

| Part | Where | What it is |
| --- | --- | --- |
| Lint ruleset | `lib/analysis_options.yaml` | very_good_analysis 10.2.0 (frozen in `lib/analysis_options.10.2.0.yaml`) plus our curation; every app `include:`s it |
| `neon_lints` | `plugin/` | native analyzer plugin (`analysis_server_plugin`) with our rules, reported as `[NEON] ...` |
| Layout | `plugin/lib/layout.dart` | where an app keeps each kind of code (pages, cubits, providers, ...); rules and checks ask a role, never a folder |
| `neon-check` | `checker/`, `bin/neon-check` | the runner: every check in a fixed order, the ratchet baseline, triggers, commands |
| Packs | `packs.yaml` | named groups of rules and checks an app switches on together |
| Presets | `presets/*.yaml` | `base` (every app), `admin` (a kit administration such as neoncode), `app` (a single mobile app such as vernakapp) |
| Git hooks | `hooks/` | `pre-commit`, `pre-push` run their trigger; an app's own hooks still run first |
| Integration runner | `integration/run.sh` | runs flows on a driver: `web-server` (Chrome + chromedriver), `device`, `none` |
| Rule catalog | `plugin/rule_catalog.json` | every rule's description, message and correction, generated from the rule classes (`plugin/tool/generate_rule_catalog.dart`); the brief and `explain` read it |

In the app stay only what belongs to it: `neon_check.yaml`, the baseline
`tool/lint_baseline.json` and the tests.

## Configuring an app: `neon_check.yaml`

The configuration is `presets/base.yaml`, then the preset the app names, then
the app's own `neon_check.yaml`, merged in that order (maps key by key, a list
or a value replaces). What the tool can see it detects instead of asking:

| Detected | From |
| --- | --- |
| project name | `name:` in `pubspec.yaml` (also the default test suite) |
| flavours | folders of `lib/flavors/` and `lib/main_<flavor>.dart` |
| languages | `assets/translations/*.json` |
| platforms | `web/`, `android/`, `ios/`, ... |
| router, providers and help files | the layout roles, expanded per flavour |

So an app's file holds only what is really its own. neoncode:

```yaml
preset: admin
default_base: feature/testing
page_help:
  exempt: [vernak_login_page.dart, vernak_register_page.dart]
tests:
  suites:
    vernak: [lib/pages/vernak, lib/bloc/vernak, ...]
    doordrop: [lib/pages/neoncode/neoncode_doordrop_*, ...]
```

A single mobile app needs even less:

```yaml
preset: app
default_base: main
layout:
  providers: lib/app/app_providers.dart
```

`neon-check explain` prints what was detected and resolved: packs, steps,
triggers, layout, suites, flows, hooks, and any configuration error.

| Key | Meaning |
| --- | --- |
| `preset` | `admin` or `app` (files in `presets/`) |
| `default_base` | branch the changed files are compared against when the branch records no `branch.<name>.neonBase` |
| `packs` / `skip_packs` | replace the preset's packs / drop some of them |
| `rules` | one rule: `true`, `false`, `error`, `warning`, `info` |
| `layout` | roles whose folders differ from the default (below) |
| `tree.use` | optional folders of the canonical `lib/` tree the app has (`[flavors]`); the folder names themselves are fixed (below) |
| `flavors`, `translations.languages` | only when detection is wrong |
| `tests.suites` | `name: [source globs]`: which sources select `test/<name>` and the `integration_test/<name>_*` flows |
| `tests.shared` | sources whose change runs every suite (preset) |
| `integration` | `driver` (`web-server`, `device`, `none`), `device`, `defines_file`, `require_flow_for_pages`, `exempt_pages` |
| `triggers` | when what runs (below) |

A mistake (an unknown preset, pack, rule or layout role) is a hard
`config_invalid` failure, never silently ignored.

### Packs

The analyzer reads only `analysis_options.yaml`, so the `config_sync` step
writes the rules of the enabled packs there (between `# >>> neon-check` and
`# <<< neon-check`, every rule `true` or `false`). Edit `neon_check.yaml`, never
that block. The packs and their rules are listed under [Rules](#rules).

### Layout

Every rule and check that depends on where code lives asks a role. Defaults
follow the shared structure; an app overrides only the roles it keeps
elsewhere. Patterns are root-relative: a trailing `/` is a folder, `*` stays in
one segment, `**/` crosses folders, `{name}` is one segment that must repeat
the same text (`lib/flavors/{flavor}/{flavor}_router.dart`).

| Role | Default |
| --- | --- |
| `pages` | `lib/pages/` |
| `subtitled_pages` | `lib/pages/` |
| `features` | `lib/features/` |
| `global_widgets` | `lib/global_widgets/` |
| `bloc` | `lib/bloc/` |
| `app_wide_cubits` | `lib/bloc/*/app_wide/` |
| `repository` | `lib/repository/` |
| `model` | `lib/model/` |
| `enums` | `lib/model/enums/*/` (the scope folders; neoncode lists them: `common`, `vernak`, `neoncode`, `doordrop`, `quest`) |
| `role_enums` | `lib/model/enums/` |
| `providers` | `lib/flavors/{flavor}/{flavor}_providers.dart` |
| `routing` | `lib/flavors/` |
| `app_root` | `lib/app/bootstrap.dart` |
| `routers` | `lib/flavors/{flavor}/{flavor}_router.dart` |
| `dialog_helper` | `lib/utils/utils.dart` |
| `tokens` | `lib/utils/ui/tokens/` |
| `widget_dimens` | `lib/**/*_dimens.dart` |
| `legacy_dimens` | `lib/**/app_dimens.dart` |
| `text_styles` | `lib/**/*_text_styles.dart`, `lib/utils/ui/app_style.dart` |
| `colors` | `**/theme/`, `**/ui/app_icon.dart`, `**/ui/app_style.dart`, `lib/model/`, `**/color_editor*`, `**/color_editor*/`, `test/support/` |
| `assets_registry` | `lib/**/app_assets.dart` |
| `logger` | `lib/utils/helpers/log_utils.dart` |
| `responsive` | `lib/utils/ui/app_responsive.dart` |
| `catalog_previews` | `lib/**/widget_catalog/previews/` |

The plugin reads the `layout:` section from the app's `neon_check.yaml`
itself (presets never set a layout, so both sides agree).

### The `lib/` tree

Every app has the same `lib/` (NCC0000058). The base preset fixes the folder
of every role directly under `lib/`; an app never renames one or adds its own.
Optional folders exist only where the app switches them on:

```yaml
# presets/base.yaml
tree:
  folders: [app, bloc, model, repository, features, pages, global_widgets, utils, hive]
  optional: [flavors]
  entrypoints: [main.dart, 'main_*.dart']

# an app with flavours, in its neon_check.yaml
tree: {use: [flavors]}
```

The `layout_tree` step reports every other folder directly under `lib/` (as
`lib/<name>/`) and every file there that is no entrypoint (a generated
`hive_registrar.g.dart` belongs in `lib/hive/`). An app setting `tree.folders`,
`tree.optional` or `tree.entrypoints`, or using a folder that is not optional,
is a `config_invalid` failure. An app without flavours keeps its router under
`app/` (role `routers`).

### Layer folders

A widget's folder says its layer: its `{@category}`, mapped to one folder
name, the same everywhere (rule `category_matches_folder`):

| `{@category}` | Folder |
| --- | --- |
| Component | `components/` |
| Layout | `layouts/` |
| Behavior | `behaviors/` |
| Pattern | `patterns/` |
| Template | `templates/` |
| Skeleton (a skeleton that is a piece of its own) | `skeletons/` |
| Feature (a kit piece or a part) | `features/` |
| any class named `*Dialog` / `*Sheet` | `dialogs/` |

The layer folder sits directly under each owner of the kit
(`lib/global_widgets/global/components/app_switch/app_switch.dart`), in every
`widgets/` folder of a page, feature or kit piece
(`lib/pages/vernak/vernak_company_page/widgets/patterns/company_users_block.dart`)
and below a kit's `src/`. A grouping folder may stand on either side of it
(`global/stats/components/...` or `global/components/stats/...`). Parts keep
no folder, dimens or skeleton of their own, and each carries its own
`{@category}`. A `<name>_skeleton.dart` stays beside its widget and moves with
it; pages stay in `lib/pages/<app>/<page>/` and feature pieces in
`lib/features/<product>/<feature>/`, under no layer folder.

### Where a widget lives, and what UI may do

Placement (NCC0000060, rule doc `feature_placement`), first match wins:

1. it reads no state (no cubit, context getter or repository): the kit
   (`lib/global_widgets/**`), or a part of the one page that uses it;
2. it reads state and only one page uses it: a part of that page
   (`<page>/widgets/`);
3. it reads state or drives a whole flow, and several pages, a shell or both
   administrations use it: a Feature in `lib/features/<product>/<feature>/`.

`feature_reads_state` reports a Feature that reads no state and the step
`feature_used_once` a feature only one page imports. UI only draws: the cubit
of a page or feature is its controller (no second controller layer); every
computation over data happens in the cubit, which emits ready-to-draw data
(filtered and sorted IDs, formatted numbers and dates, flags);
`no_data_logic_in_ui` reports filtering, sorting and arithmetic over model
data and the clock in widgets. Pure stateless logic goes to
`neon_flutter_utils` or `lib/utils/helpers/`.

### Triggers

| Trigger | Called by | Scope | Steps (base preset) | Changes files | Integration |
| --- | --- | --- | --- | --- | --- |
| `edit` | Claude Code PostToolUse after a `.dart` edit | the edited file | `analyze`, `ignores` | no | off |
| `stop` | Claude Code Stop hook; a bare `neon-check` | changed against the base | all | yes (format, fix, order, generators) | affected flows |
| `commit` | `hooks/pre-commit` | staged | config, format, fix, analyze, ignores, translations | no | off |
| `push` | `hooks/pre-push` | changed | none (CI and `/done` run everything) | no | off |
| `ci` | CI (`.woodpecker.yml`), `/done` | everything | all | no | all |

An app changes a trigger in its `triggers:` (for example
`stop: {integration: off}` to keep turns fast, or steps for `push`).

## Commands

```bash
neon-analyze-flutter/bin/neon-check                    # the stop trigger: changed files, all steps, affected flows
neon-analyze-flutter/bin/neon-check --all              # the whole project (fixes what it can)
neon-analyze-flutter/bin/neon-check --trigger ci       # exactly what CI and /done run
neon-analyze-flutter/bin/neon-check explain            # what was detected and will be checked
neon-analyze-flutter/bin/neon-check integration [flows]  # run flows on the driver, output on the terminal
neon-analyze-flutter/bin/neon-check brief <file>       # what a file must follow (what the AI gets before editing it)
neon-analyze-flutter/bin/neon-check next               # the next burndown batch: rule, exact findings, how
neon-analyze-flutter/bin/neon-check burndown start --base <branch>   # bring the baseline to zero, driven by the hooks
neon-analyze-flutter/bin/neon-check burndown status|skip|unskip|stop
neon-analyze-flutter/bin/neon-check --rule <rule>      # every finding of one rule (exit 0)
neon-analyze-flutter/bin/neon-check --zero <rule>      # that rule must have no finding at all (migrations)
neon-analyze-flutter/bin/neon-check --update-baseline  # today's findings become the baseline (a new rule)
neon-analyze-flutter/bin/neon-check --step a,b         # only these steps; --list shows them
neon-analyze-flutter/bin/neon-check install            # git hooks (core.hooksPath)
neon-analyze-flutter/bin/neon-check init               # start a new app (below)
```

Scope flags override the trigger's: `--changed`, `--all`, `--staged`,
`--files a b`, `--base <branch>`; `--ci` never changes a file;
`--integration off|affected|all`; `--max-failures <n>`.

## The steps

They run in this order and the run stops at the first failing step. A step runs
only when a pack of the app lists it and the run touches what it checks.

| Step | Pack | Does | Auto-fix |
| --- | --- | --- | --- |
| `config_sync` | core | `neon_check.yaml` is valid; the analyzer section matches the packs | yes |
| `format` | core | `dart format --line-length 120` | yes |
| `fix` | core | `dart fix --apply` (core fixes; plugin fixes are IDE-only) | yes |
| `analyze` | core | `dart analyze` on the root (`--all`) or on file paths, then the ratchet | no |
| `ignores` | core | no `// ignore:` for a `[NEON]` rule | no |
| `rule_docs` | core | every written ESME rule that governs app code ends with an `Enforced by:` or `Not enforced:` line, and the checks it names exist (skips without an export) | no |
| `translations_parity` | core | same keys in every language file | no |
| `translations_dashes` | core | no `—` `–` `−` `--` in values | no |
| `translations_missing` | core | every literal `tr('key')` exists | no |
| `translations_unused` | core | keys no code uses (`--all` only) | `--prune-translations` |
| `translations_order` | core | keys in the primary file's order | yes |
| `assets` | core | registry paths exist (in the app, or in the dependency the registry names as their package); unused asset files (`--all`) | no |
| `layout_tree` | core | directly under `lib/` only the folders of the canonical tree (`tree:`) and the entrypoints; ratchet `layout_tree` | no |
| `feature_used_once` | kit | a feature (the entry file `<feature>/<feature>.dart` of the `features` role declaring a `{@category Feature}` class) imported directly by exactly one page folder (`.../<name>_page/`) and by nothing else outside its folder (no shell, router, other feature, shared `pages/<app>/widgets/`) belongs into that page; ratchet `feature_used_once` | no |
| `catalog_index` | catalog | widget catalog index regenerated | yes |
| `catalog_previews` | catalog | every widget in `preview_required` has a preview | no |
| `providers` | flavors | every typed context getter reads a cubit its router or shell, the app startup (`app_root`) or a `showCustomModalBottomSheet(create:)` provides | no |
| `page_help` | admin | every page has `help:` and its help keys (one entry per flavour with a help enum) | no |
| `generated` | core | `*.g.dart` match their sources (build_runner) | yes |
| `test_existence` | bloc, go_router | every cubit has `<name>_cubit_test.dart` (bloc), every GoRoute `<route>_route_test.dart` (go_router); ratchet `test_missing` | no |
| `integration_pages` | integration | every page has a flow that imports it or finds its class (ratchet `integration_missing`) | no |
| `tests` | core | `flutter test`, suites selected by the changed files | no |
| `coverage` | bloc | changed lines under `tests.coverage.sources` covered by the tests that ran (hard `coverage_low`) | no |
| `integration` | integration | the flows the change affects (`stop`) or all (`ci`) on the driver; a failing flow is hard | no |

**Scope.** `--changed`: files changed against the merge base with the branch
base (`--base`, else `branch.<name>.neonBase`, else `default_base`), plus
uncommitted and untracked files. `--staged`: the commit. `--files`: a list.
`--all`: everything.

**Ratchet.** Every finding except compile errors, tool crashes, configuration
errors, failing tests and flows and low coverage is counted per rule and file
against `tool/lint_baseline.json`. More than the baseline fails; fewer lowers
the baseline automatically, so a fixed violation cannot come back. The
baseline is written by `--update-baseline` (when a rule or gate lands) and is
never raised by hand. `--ci` never writes it.

**Test suites.** `tests.default_suite` (the project name) always runs and owns
every test outside the other suites' folders; a changed source matching a
suite's globs (or a changed test in its folder) adds that suite; a
`tests.shared` source runs every suite.

**Integration flows.** A flow is `integration_test/<suite>_<flow>_test.dart`;
shared steps live in subfolders. `affected` runs a changed flow, the flows
that import a changed shared step, and the flows of the suites the changed
`lib/` sources select (a shared source or `pubspec.yaml`: every flow). Tests,
translations and assets select none. Credentials go in `defines_file`
(default `integration_test/defines.json`, never committed), passed as
`--dart-define-from-file`. A missing driver (no chromedriver, no device) skips
with a notice; `NEON_INTEGRATION_REQUIRED=1` turns that into a failure.

## Burndown: bringing a broken app to zero

The baseline keeps old findings from breaking every session, but a project
also needs them gone. The burndown does that without a prompt:

```bash
neon-analyze-flutter/bin/neon-check burndown start --base feature/testing
```

From then on, in every Claude Code session of that checkout (neon-flutter
plugin hooks):

1. **Session start**: without a branch yet, the session creates one ticket
   (change) in ESME, the branch `change/<KEY>-lint-burndown` from the base,
   records it (`burndown start --branch <b> --ticket <KEY>`) and begins; with
   one, it continues.
2. **`neon-check next`** names the next rule and a batch of its findings
   (`burndown.batch`, 40), with the rule's fix and the procedure: fix, run
   `neon-check` (it lowers the baseline), commit, note the ticket, `next`.
   The order is `burndown.yaml`: phases from local fixes over tokens, the kit,
   where cubits live, UI logic and pages to the missing tests; unlisted rules
   last, smallest first.
3. **Stop hook**: while the check is green and `next` has work on the burndown
   branch, the turn does not end, up to `burndown.max_turns_per_session` (30);
   the next session continues after any message.
4. **Integration flows** do not run at the end of burndown turns
   (`burndown.stop_integration: off`, the burndown touches shared code all
   the time); they run with `--trigger ci` at the end of a phase and before
   the PR.
5. **A rule that needs a person** (a false positive, a product decision) is
   handed back with `burndown skip <rule> --reason "..."`; `burndown status`
   and the finish text list them.
6. **Empty baseline**: `--trigger ci` green, `burndown stop`, `/done` with a
   PR into the base branch.

The state is `.neon-check/burndown.json` in the checkout (gitignored). A
person still confirms the ticket transitions, decides the skipped rules and
reviews the PR.

## Written rules and checks name each other

The ESME context layer holds the written rules (the why, for people and the
AI); the session-start hook exports them to `.claude/rules/shared/` and Claude
Code loads each one when a file of its `paths:` is read or edited. The checks
here are the enforcement. The two must not drift apart, so every written rule
that governs app code ends with one line:

```
Enforced by: `no_raw_color`, `no_raw_dimension`
Not enforced: finding an existing component is a judgement.
```

The `rule_docs` step fails on a rule without that line and on a name that is
no neon_lints rule or neon-check step; `neon-check explain` lists the enabled
lint rules no written rule explains yet. A fix always goes to ESME
(`context_update`; a project overrides a company rule with `?scope=project`),
never to the exported file.

## Adopting the tool in an app

```bash
git submodule add git@github.com:neoncode-app/neon-analyze-flutter.git neon-analyze-flutter
# pubspec.yaml dev_dependencies: neon_analysis: {path: neon-analyze-flutter}
neon-analyze-flutter/bin/neon-check init            # neon_check.yaml (preset admin or app), git hooks, analyzer section
neon-analyze-flutter/bin/neon-check explain         # is everything detected right? fix layout / suites if not
neon-analyze-flutter/bin/neon-check --all --update-baseline   # today's findings become the baseline: nothing breaks
neon-analyze-flutter/bin/neon-check burndown start --base main   # then the AI brings it to zero, session by session
```

From then on the Claude Code hooks (neon-flutter plugin) and the git hooks run
it by themselves. The neon-flutter plugin recognises an app by its
`neon_check.yaml`.

## Rules

Every `[NEON]` rule reports a warning, so a violation makes `dart analyze`
exit with code 2. Only `dart analyze` runs the plugin, from the package root or
on file paths (`dart analyze lib`, a directory, skips it; so does
`flutter analyze`). After changing the plugin source clear its compiled copy:
`rm -rf ~/.dartServer/.plugin_manager`. Silencing a rule with
`// ignore: neon_lints/<rule>` fails the `ignores` step: a false positive is
fixed in the plugin.

### `core`

Every Flutter app. Formatting, analyzer, translations, assets, generated code, the canonical lib/ tree, unit tests, and the rules any code base follows.

Checks: `config_sync`, `format`, `fix`, `analyze`, `ignores`, `translations_parity`, `translations_dashes`, `translations_missing`, `translations_unused`, `translations_order`, `assets`, `generated`, `layout_tree`, `tests`.

| Rule | What it enforces |
| --- | --- |
| `avoid_bang` | no null-assertion `!` |
| `no_widget_builder_method` | no private `Widget _buildX()` methods |
| `no_raw_color` | no `Color(0x..)` / `Colors.x` outside theme files |
| `no_raw_asset_path` | no `'assets/...'` literals outside `AppAssets` |
| `no_debug_print` | no `debugPrint` outside `lib/utils/helpers/log_utils.dart` |
| `no_dash_in_strings` | no `—` `–` `−` in string literals (logs and error messages allow-listed) |
| `no_hardcoded_ui_string` | no literal text in `Text(...)` / `label:` / `title:` / ... in UI code |
| `no_repository_in_ui` | no class from `lib/repository/` in UI code |
| `no_http_in_ui` | no `package:http` / `package:dio` import in UI code |
| `use_shared_utils` | the raw APIs `neon_flutter_utils` wraps: `DateFormat(` / `NumberFormat(`, `toStringAsFixed(` in UI code, `launchUrl(` / `canLaunchUrl(`, `Clipboard.` outside `AppCopyButton` / `AppCopyField`, `jsonDecode(` outside `repository`, `RegExp(` with an e-mail or phone pattern, `kIsWeb` / `Platform.` outside UI code, a `Timer(` stored in a cubit field (use `Debouncer`) |

### `bloc`

Cubits. BaseCubit, sealed states, cubits only in providers, typed context getters, alerts from cubits, a test for every cubit, coverage of changed cubit code.

Checks: `test_existence`, `coverage`.

| Rule | What it enforces |
| --- | --- |
| `extend_base_cubit` | cubits extend `BaseCubit` |
| `use_context_getters` | `context.read/watch/select` and `BlocProvider.of` only in the providers files (`lib/flavors/<f>/<f>_providers.dart`, plus an app-wide one such as `lib/app/app_providers.dart` when the layout lists it) |
| `cubit_created_in_provider` | a bloc / cubit is constructed only in a provider's `create:` callback, or in the app startup (`app_root`) for the app-wide cubits the router needs before it exists |
| `no_cubit_call_in_lifecycle` | no cubit method call directly in `initState`, `didChangeDependencies`, `build` |
| `no_provider_value` | no `BlocProvider.value` of a cubit held in a `State` field |
| `cancel_subscriptions_in_close` | `stream.listen` in a cubit stored in a field and cancelled in `close()` |
| `alert_only_in_cubit` | no `AlertCubit` in `lib/pages`, `lib/features`, `lib/global_widgets` |
| `state_is_sealed` | the state of a `BaseCubit<S>` is `sealed` (except `lib/bloc/<app>/app_wide/`) |
| `no_status_enum_state` | no `XStatus` enum field in a state class under `lib/bloc` |
| `no_state_enum_branching` | UI code never branches (`switch`, `==`) on an enum field of a cubit state; each value is a state subclass |
| `result_handles_unauthorized` | no neonapi `Result.when(...)` without `unauthorized:` (it runs no branch on a 401); use `handleError(error:, success:)` |
| `cubit_only_state` | state is a Cubit extending `BaseCubit` with a sealed state, nothing else (NCC0000063): no class extending / mixing `Bloc` (events), no `ChangeNotifier()` and no class extending or mixing in `ChangeNotifier` outside the widget kit (a kit controller such as `SaveRequiredHintController` is local UI state, like `TextEditingController`), no `StateNotifier`, no `package:provider` widgets (`Provider`, `ChangeNotifierProvider`, `MultiProvider`, `Consumer`, `Selector`, ...; flutter_bloc's `BlocProvider` / `RepositoryProvider` and `context.read` stay), no import of `package:riverpod`, `flutter_riverpod`, `hooks_riverpod` or `get`. Type-resolved, table-driven (`plugin/lib/src/banned_api/`) |
| `no_value_notifier_state` | no `ValueNotifier(...)` construction and no class extending `ValueNotifier` outside `lib/global_widgets` (the `global_widgets` role): the value is a field of the cubit state. Reading a `ValueListenable` (Hive `listenable()`, Flutter controllers) and local UI state of a kit component stay |

**The state convention** these rules converge on (one shape for every page
cubit, so the UI is always `switch (state)` over a closed set):

```dart
sealed class XState {               // the data every state shows + derived getters
  final List<Item> items;
  const XState({this.items = const []});
  bool get isEmpty => items.isEmpty;
}
final class XInitial extends XState { const XInitial(); }
final class XLoading extends XState { const XLoading({super.items}); }  // previous data stays visible
final class XLoaded extends XState {
  final bool isSaving;              // busy markers only on Loaded
  const XLoaded({required super.items, this.isSaving = false});
}
final class XError extends XState {
  final String message;             // the last data stays visible
  const XError(this.message, {super.items});
}
```

- A page with modes (tabs, a list and an archive) has one subclass per mode,
  not an enum the UI switches on (`no_state_enum_branching`).
- A value the user picks (a period, a filter) may stay a field, as long as the
  UI only shows it and passes it back.
- Sections that load independently get a nested sealed field
  (`sealed class XHistory` with `Loading` / `Loaded(items)` / `Error`).
- App-wide cubits (`lib/bloc/<app>/app_wide/`) are exempt from
  `state_is_sealed`: a session or the rules are one long-lived value.

### `presentation`

No logic in UI. Dialogs and navigation through presentation events, no setState in pages, page and feature State holds controllers only, no computations over model data in widgets.

| Rule | What it enforces |
| --- | --- |
| `dialog_only_in_listener` | `Utils.showCustomModalBottomSheet` / `Utils.openModalBottomSheet` only in a presentation listener or a `show*` function |
| `no_dialog_result` | the result of a dialog (`showCustomModalBottomSheet`, `show*` Future) is never used, no code after an awaited dialog |
| `dialog_opener_returns_void` | a top-level `show*` function or static `show*` method that opens a dialog (calls `Utils.showCustomModalBottomSheet` / `Utils.openModalBottomSheet`, or forwards to another app `show*` Future) returns `void`; it opens the dialog with `Utils.openModalBottomSheet` (NCC0000062) |
| `no_unawaited_dialog_opener` | in UI and routing code no `unawaited(showX(...))` around an app `show*` function or method returning a Future (reported at the opener: make it `void`), and no `unawaited(Utils.showCustomModalBottomSheet(...))` outside a `show*` opener; the listener line is `if (event is X) return showX(context, event);`. Background work (`unawaited(cubit.load())`) stays |
| `listener_is_mapping` | a presentation listener only maps `event is X` to one call: no variables, cubit reads, awaits or other branching |
| `no_navigation_in_ui` | no go_router navigation in UI code; `context.pop()` only as a pure Cancel or for `CloseDialog` |
| `ui_callback_calls_cubit` | `on*:` in pages is a cubit tear-off, one cubit call or a forwarded callback |
| `no_setstate_in_pages` | no `setState` in `lib/pages`, `lib/features` |
| `no_private_methods_in_page_state` | a page or feature `State` declares only lifecycle methods (`didChangeAppLifecycleState` included) and `build` |
| `stateful_page_only_for_controllers` | a page or feature `State` holds only controllers, focus nodes, timers, subscriptions, keys (by type name) |
| `no_editor_controller_in_pages` | no `*EditorController` and no `.validate()` in pages |
| `no_data_logic_in_ui` | in a `Widget` / `State` class of pages, features and the kit: no `where` / `firstWhere` / `sort` / `fold` / `reduce` / `any` / `every` / `expand` on an `Iterable` of app models (classes of the `model` role, enums excluded), no `DateTime.now()`, no arithmetic (`+ - * / ~/ %` on numbers) with an operand that reads a field of an app model object (`coupon.price * 2`); mapping data to widgets, comparisons and layout maths from number parameters stay allowed. The cubit computes and emits ready-to-draw data |

### `models`

Data models. Enums in lib/model/enums/<scope>/, one declaration per model file, models only in lib/model/ and nothing else in it, no helper functions in models, serialization generated by json_serializable, no dynamic in models.

| Rule | What it enforces |
| --- | --- |
| `enum_in_enums_folder` | every enum of app code lives in its own file `lib/model/enums/<scope>/<name>.dart` (role `enums`: the scope folders, `common/` or a project), the file named after it; enums of pages, cubits, states, features, utils and other model folders, private ones included, are findings. Only the kit's variant enums in `lib/global_widgets/**/*_dimens.dart` stay; a kit enum declared beside its widget is reported with the piece's dimens as its place (NCC0000065) |
| `one_declaration_per_model_file` | a file of the `model` role declares one class, enum, mixin, extension, extension type or typedef; every further one is reported (generated parts skipped) |
| `models_only_in_model` | outside the `model` role no class with a `fromJson` constructor / static method, a `toJson` method or `@JsonSerializable`, and no class (widgets and `*Labels` aside) in a `*_model.dart` / `*_models.dart` file; inside it no widget or `State`, no `*Dimens` class, no import of `package:flutter/material.dart` / `widgets.dart` / `cupertino.dart` (`Color` comes from `dart:ui`) and no import of a UI file (pages, features, the kit) |
| `no_logic_in_models` | no top-level function (or top-level getter / setter) in the `model` role: parsing through json_serializable and its converters, derived values as getters of the model, helpers in `lib/utils/` |
| `model_uses_json_serializable` | in the `model` role a class with a `fromJson` constructor / static method or a `toJson` method is annotated `@JsonSerializable` and those members return the generated `_$XFromJson(json)` / `_$XToJson(this)`; special cases through `@JsonKey`, `@JsonEnum` and the converters of `package:neon_flutter_utils/json.dart`, project defaults in the app's `build.yaml` (NCC0000066). `JsonConverter` implementations are no models |
| `no_dynamic_in_models` | no field, constructor parameter or getter of a class, enum or mixin in the `model` role is `dynamic`, `Object` / `Object?` or has one of them as a type argument (`Map<String, dynamic>`, `List<dynamic>`); the `fromJson(Map<String, dynamic> json)` parameter, methods (`toJson()`), `this.x` parameters (the field is reported) and getters overriding an inherited one (`body` of a neonapi request) are allowed |

### `go_router`

Navigation with go_router. No Navigator, cubits provided in the route builders, a test for every route.

Checks: `test_existence`.

| Rule | What it enforces |
| --- | --- |
| `no_navigator` | no `Navigator.*`; navigate with go_router (`context.pop` / `go` / `push`) |
| `provider_in_router` | `BlocProvider` / `MultiBlocProvider` only in the routing files (`lib/flavors/**`), the app startup (`app_root`, `lib/app/bootstrap.dart`) and the dialog helper (`lib/utils/utils.dart`) |

### `responsive`

Screen size only through app_responsive.dart. No MediaQuery size, kIsWeb, Platform or numeric breakpoints in UI.

| Rule | What it enforces |
| --- | --- |
| `no_media_query_size` | screen size only through `lib/utils/ui/app_responsive.dart` |
| `no_kisweb_in_ui` | no `kIsWeb` in UI code |
| `no_platform_in_ui` | no `Platform.isX`, `defaultTargetPlatform` in UI code |
| `no_layout_builder_in_pages` | `LayoutBuilder` only in `lib/global_widgets` |
| `no_raw_breakpoint` | no width compared with a numeric literal |

### `kit`

The shared widget kit (lib/global_widgets). Kit widgets instead of raw Flutter, layering, {@category}, one folder per piece with its dimens and skeleton, the folder of a widget says its layer, the scale only in dimens files, named text styles, no tr() in the kit and *Labels only in the kit, a Feature reads state and serves several pages.

Checks: `feature_used_once`.

| Rule | What it enforces |
| --- | --- |
| `use_kit_widgets` | raw Flutter widgets and APIs the admin widget kit replaces; the message names the kit widget to use |
| `no_tr_in_global_widget` | no `tr()` under `lib/global_widgets/` |
| `labels_only_in_kit` | only the kit takes `*Labels` objects: no class named `*Labels` in a page or feature, no `*Labels` field or constructor parameter on a `{@category Feature}` class or a page widget; features and pages call `tr()` where they draw, per-flavour wording comes from `FlavorConfig` |
| `global_widgets_layering` | `lib/global_widgets` never imports `lib/pages` or `lib/features` |
| `component_has_no_state_access` | a Component / Layout / Pattern file imports no bloc and reads no provider |
| `global_widget_has_category` | public kit / feature widgets end their doc comment with a valid `{@category}` |
| `kit_src_internal` | a kit's `src/` is imported only from inside that kit |
| `no_raw_dimension` | no numeric size / padding / radius / gap literal outside `lib/utils/ui/tokens/`, `*_dimens.dart`, `*_text_styles.dart` |
| `dimens_private_to_widget` | an app `<Widget>Dimens` is used only inside its widget's folder |
| `scale_only_in_dimens` | the scale (`AppSpacing`, `AppRadius`, ... in `lib/utils/ui/tokens/`) is read only by `*_dimens.dart` files; every other file uses its own dimens |
| `no_app_dimens` | no reference to the old `AppDimens` (ratchet during the migration) |
| `component_takes_variant` | `{@category Component}` constructors take no raw dimension parameters (primitives allow-listed) |
| `piece_in_own_folder` | every public widget of the kit, features and pages lives in `<name>/<name>.dart` (below its layer folder or, during the migration, where it is); parts go into subfolders of their piece's folder |
| `piece_has_skeleton` | every piece except layouts, behaviors, templates, skeletons, dialogs and sheets has `<name>_skeleton.dart` declaring `<Name>Skeleton` beside it |
| `category_matches_folder` | the `{@category}` of a public widget in the kit or in a `widgets/` folder matches its [layer folder](#layer-folders) (`*Dialog` / `*Sheet` in `dialogs/`); a part of a page without `{@category}` is reported too |
| `no_raw_text_style` | no `TextStyle(...)` / `copyWith(` other than `color:` outside the text style files |
| `feature_reads_state` | a `{@category Feature}` class reads state: in it, its `State` or the private classes of its file there is a typed context getter (an extension getter of a providers file), a provider read, a bloc / cubit type or a type of the `bloc` or `repository` roles, or another Feature it builds; otherwise it belongs to the kit or to its one page |

### `catalog`

The widget catalog page. Its generated index is current and every kit widget has a live preview.

Checks: `catalog_index`, `catalog_previews`.

### `admin`

Administration pages. Every page stands on a template with title and subtitle, access is declared on the route, roles through enums, a help dialog per page.

Checks: `page_help`.

| Rule | What it enforces |
| --- | --- |
| `page_uses_template` | `build()` of a `*Page` returns, through bloc / presentation wrappers, a `{@category Template}` widget |
| `page_has_title_subtitle` | `AppContentPage` gets both `title:` and `subtitle:` |
| `no_access_guard_in_pages` | no `RoleGuard` / access-denied widget in pages (access is on the route) |
| `no_role_literal` | no backend role strings outside `lib/model/enums/` |

### `flavors`

Several flavours in one code base. Every typed context getter reads a cubit its flavour's router or shell provides.

Checks: `providers`.

### `integration`

Integration tests of the real app. The flows the change affects run on the configured driver, and every page has a flow.

Checks: `integration_pages`, `integration`.

### Banned-API rules (`use_kit_widgets`, `no_navigator`, `use_shared_utils`)

All three are driven by a table in their source file: one `BannedApi` row per
banned API, with its replacement and the owner files (paths relative to `lib/`)
that implement the replacement and may therefore still use the raw API. Adding
a ban is one row. Matching is type-resolved (element name plus declaring
package), so an app class that happens to be called `Switch` is not flagged
and an import prefix does not hide a banned API. A row flags constructing the
class, constructor tear-offs, static member access (`Icons.add`,
`Navigator.of`), calls of banned top-level functions (`showDialog`) and,
for whole packages, imports (`package:fl_chart`). Type annotations are never
flagged. A row can also give ownership to every file that declares a class
with a given `{@category ...}`, which is how any template may use `Scaffold`,
or to every file that declares one of the named classes (`AppCopyField` owns
`Clipboard`). A row may also ban instance methods of SDK types
(`toStringAsFixed` on `num`) and top-level variables (`kIsWeb`), name an SDK
library as its package (`dart:io`), apply only to UI code, only outside it, only
in some layout roles or not in some (`jsonDecode` is allowed in `repository`),
and add a condition on the node (`RegExp` only with an e-mail or phone pattern,
`Timer` only when stored in a cubit field).
Only files under `lib/` are checked; generated files (`*.g.dart`,
`*.freezed.dart`) are skipped.

## Quick fixes

Plugin quick fixes are IDE-only. `dart fix --apply` does not apply them
("Nothing to fix!"), and `dart fix --code=<plugin rule>` rejects the code as
unknown (verified on Dart 3.12.2 with `analysis_server_plugin` 0.3.10). Bulk
mechanical migrations need a codemod script instead.

## Adding or changing rules

Use the **`neon-rule-author`** agent: it holds the plugin API, the rule
template and the submodule workflow. A new rule:

1. a file in `plugin/lib/src/`, registered in `plugin/lib/main.dart`;
2. folders through `RuleLayout.of(context)` (`plugin/lib/src/support/rule_layout.dart`),
   never a hard-coded path; a folder no role covers gets a new `LayoutRole`;
3. tests in `plugin/test/` (`analyzer_testing`): a violating case, a clean case,
   the allow-listed owner, and a layout override where it applies;
4. exactly one pack in `packs.yaml` (`checker/test/config_test.dart` checks it),
   with `where:` when it is about one kind of code only;
5. `cd plugin && dart run tool/generate_rule_catalog.dart` (the brief's texts;
   `plugin/test/rule_catalog_test.dart` fails while it is stale);
6. in each app with that pack: `neon-check --all --update-baseline`.

```bash
cd plugin && dart test
cd checker && dart test
```

Tests resolve against small stub packages (`plugin/test/support/stub_packages.dart`),
so a rule that matches a Flutter, `intl` or `fl_chart` element needs that
element stubbed there. Plain YAML lints are switched in the `linter: rules:`
block of `lib/analysis_options.yaml`.

## Updating the very_good_analysis base

`git fetch upstream && git merge upstream/main`, then point the `include:` in
`lib/analysis_options.yaml` at the newer `analysis_options.<version>.yaml`
(add that file from upstream).
