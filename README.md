# neon-analyze-flutter

Shared analyzer setup for the Neon Code Flutter apps (vernakapp, neoncode,
baseapp). Two parts in one repo:

- **`lib/analysis_options.yaml`** — the lint ruleset: a fork of very_good_analysis
  (VGV 10.2.0, frozen in `lib/analysis_options.10.2.0.yaml`) plus our curation.
- **`plugin/`** — `neon_lints`, a native analyzer plugin (built on Dart's
  first-party `analysis_server_plugin`) with our own rules. Its diagnostics show
  up in `flutter analyze` prefixed with `[NEON]`.

## How the apps use it

Added to each app as a git submodule at `neon-analyze-flutter/`, then in the
app's `analysis_options.yaml`:

```yaml
include: package:neon_analysis/analysis_options.yaml
plugins:
  neon_lints:
    path: neon-analyze-flutter/plugin
```

## Adding or changing rules

Use the **`neon-rule-author`** agent (in each app's `.claude/agents/`) — it holds
the full how-to: the plugin API, the rule template, testing, and the submodule
commit / pin-bump workflow. For plain YAML lint on/off, edit the `linter: rules:`
block in `lib/analysis_options.yaml`.

## Updating the very_good_analysis base

`git fetch upstream && git merge upstream/main`, then point the `include:` in
`lib/analysis_options.yaml` at the newer `analysis_options.<version>.yaml`
(add that file from upstream).
