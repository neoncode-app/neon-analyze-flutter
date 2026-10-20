import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/banned_api/banned_api.dart';
import 'package:neon_lints/src/support/rule_layout.dart';

/// Bans raw Flutter (and `intl` / `fl_chart`) APIs that the app's widget kit
/// replaces, and names the kit widget to use instead.
///
/// The table below says WHAT is banned: one [BannedApi] row per banned API,
/// with a stable [BannedApi.id]. WHAT REPLACES it is the app's own kit
/// (NCC0000078): an app with its own global widgets declares, per row id,
/// its widget and the files that implement it in `neon_check.yaml`:
///
/// ```yaml
/// kit:
///   gesture_detector: {use: AppTapArea, owners: [lib/global_widgets/behaviors/app_tap_area/]}
/// ```
///
/// The replacements and owners written in the table are the admin kit of
/// neoncode, the default of the `admin` preset. In any other app a row comes
/// from its `kit:` entry; a row it has not declared yet still reports, and
/// the message says to add the widget and declare it. A [BannedApi.portable]
/// row (an SVG for `Icons.x`, AlertCubit for a SnackBar) holds everywhere.
///
/// Source of the table: ticket NCR0000014, "Kit components instead of raw
/// Flutter". `Clipboard` and `DateFormat` moved to `use_shared_utils`
/// (NCR0000030), which every app runs.
class UseKitWidgets extends BannedApiRule {
  UseKitWidgets() : super(name: 'use_kit_widgets', description: _desc);

  static const _desc = "Use the app's widget kit instead of raw Flutter widgets.";

  static final LintCode code = bannedApiCode('use_kit_widgets', what: 'raw Flutter that the widget kit replaces');

  static const _kit = 'global_widgets/global';

  static const rows = <BannedApi>[
    BannedApi(
      id: 'decorated_container',
      label: 'Container(decoration:)',
      replacement: 'RoundedContainer / RoundedContainer.card',
      types: {'Container'},
      onlyWithArgs: {'decoration', 'foregroundDecoration'},
      owners: ['$_kit/rounded_container/'],
    ),
    BannedApi(
      id: 'decorated_box',
      label: 'DecoratedBox / Card / ClipRRect',
      replacement: 'RoundedContainer / RoundedContainer.card (clipBehavior for clipping)',
      types: {'DecoratedBox', 'Card', 'ClipRRect'},
      owners: ['$_kit/rounded_container/'],
    ),
    BannedApi(
      id: 'gesture_detector',
      label: 'GestureDetector',
      replacement: 'AppTapArea (tap / long press / pan without a look) or RoundedContainer(onTap:) (with a ripple)',
      types: {'GestureDetector'},
      owners: ['$_kit/app_tap_area/'],
    ),
    BannedApi(
      id: 'ink_well',
      label: 'InkWell / InkResponse',
      replacement: 'RoundedContainer(onTap:), or AppMaterialSurface(onTap:) on an elevated surface',
      types: {'InkWell', 'InkResponse'},
      owners: ['$_kit/rounded_container/', '$_kit/custom_button/', '$_kit/app_material_surface/'],
    ),
    BannedApi(
      id: 'material',
      label: 'Material',
      replacement: 'AppMaterialSurface (an ink host, an elevated surface) or RoundedContainer(onTap:)',
      types: {'Material'},
      owners: ['$_kit/app_material_surface/', '$_kit/rounded_container/', '$_kit/custom_button/'],
    ),
    BannedApi(
      id: 'mouse_region',
      label: 'MouseRegion for hover or a cursor',
      replacement:
          'AppTapArea (onHoverChanged / cursor) or RoundedContainer(onTap:) with hoverColor / hoverBorderColor',
      types: {'MouseRegion'},
      owners: ['$_kit/app_tap_area/', '$_kit/rounded_container/', '$_kit/custom_button/'],
    ),
    BannedApi(
      id: 'buttons',
      label: 'TextButton / OutlinedButton / ElevatedButton / FilledButton',
      replacement: 'CustomButton',
      types: {'TextButton', 'OutlinedButton', 'ElevatedButton', 'FilledButton', 'MaterialButton', 'CupertinoButton'},
      // The theme styles Material buttons for ThemeData (`*.styleFrom`).
      owners: ['$_kit/custom_button/', 'utils/ui/app_style.dart', 'utils/ui/theme/'],
    ),
    BannedApi(
      id: 'icon_buttons',
      label: 'IconButton / FloatingActionButton',
      replacement: 'CustomButton.icon / CustomButton.tonalIcon',
      types: {'IconButton', 'FloatingActionButton'},
      owners: ['$_kit/custom_button/'],
    ),
    BannedApi(
      id: 'switches',
      label: 'Switch / SwitchListTile',
      replacement: 'AppSwitch / AppSwitchRow',
      types: {'Switch', 'SwitchListTile', 'CupertinoSwitch'},
      owners: ['$_kit/app_switch/', '$_kit/app_switch_row/'],
    ),
    BannedApi(
      id: 'checkboxes',
      label: 'Checkbox / CheckboxListTile',
      replacement: 'AppCheckbox / AppCheckboxRow',
      types: {'Checkbox', 'CheckboxListTile'},
      owners: ['$_kit/app_checkbox/', '$_kit/app_checkbox_row/'],
    ),
    BannedApi(
      id: 'choices',
      label: 'Radio / ChoiceChip / FilterChip / SegmentedButton / ToggleButtons',
      replacement: 'AppChoicePills / AppSegmentedControl / AppBinaryToggle',
      types: {
        'Radio',
        'RadioListTile',
        'ChoiceChip',
        'FilterChip',
        'SegmentedButton',
        'ToggleButtons',
        'CupertinoSegmentedControl',
        'CupertinoSlidingSegmentedControl',
      },
      owners: ['$_kit/app_choice_pills/', '$_kit/app_segmented_control/', '$_kit/app_binary_toggle/'],
    ),
    BannedApi(
      id: 'text_fields',
      label: 'TextField / TextFormField',
      replacement: 'AppTextField / AppSearchField / AppCodeInput / AppInlineTimeField',
      types: {'TextField', 'TextFormField', 'CupertinoTextField'},
      owners: [
        '$_kit/app_text_field/',
        '$_kit/app_search_field/',
        '$_kit/app_code_input/',
        '$_kit/app_inline_time_field/',
      ],
    ),
    BannedApi(
      id: 'dropdowns',
      label: 'DropdownButton / DropdownMenu',
      replacement: 'AppDropdownMenu / AppLabeledDropdown',
      types: {'DropdownButton', 'DropdownButtonFormField', 'DropdownMenu'},
      owners: ['$_kit/app_dropdown_menu/', '$_kit/app_labeled_dropdown/'],
    ),
    BannedApi(
      id: 'chips',
      label: 'Chip / Badge',
      replacement: 'AppPill / AppNumberBadge / NotificationCountBadge',
      types: {'Chip', 'InputChip', 'ActionChip', 'RawChip', 'Badge'},
      owners: ['$_kit/app_pill/', '$_kit/app_number_badge/', '$_kit/notification_count_badge/'],
    ),
    BannedApi(
      id: 'dividers',
      label: 'Divider / VerticalDivider',
      replacement: 'AppDivider / ShadowDivider',
      types: {'Divider', 'VerticalDivider'},
      owners: ['$_kit/app_divider/', '$_kit/shadow_divider/'],
    ),
    BannedApi(
      id: 'expansion_tile',
      label: 'ExpansionTile',
      replacement: 'AppExpansionTile',
      types: {'ExpansionTile'},
      owners: ['$_kit/app_expansion_tile/'],
    ),
    BannedApi(
      id: 'list_tile',
      label: 'ListTile',
      replacement: 'AppListRow / AppPersonRow / AppKeyValueRow',
      types: {'ListTile'},
      owners: ['$_kit/app_list_row/', '$_kit/app_person_row/', '$_kit/app_key_value_row/'],
    ),
    BannedApi(
      id: 'circle_avatar',
      label: 'CircleAvatar',
      replacement: 'AppAvatar',
      types: {'CircleAvatar'},
      owners: ['$_kit/app_avatar/'],
    ),
    BannedApi(
      id: 'image_network',
      label: 'Image.network',
      replacement: 'AppNetworkImage',
      types: {'Image'},
      constructors: {'network'},
      owners: ['$_kit/app_network_image/'],
    ),
    BannedApi(
      id: 'network_image',
      label: 'NetworkImage',
      replacement: 'AppNetworkImage',
      types: {'NetworkImage'},
      owners: ['$_kit/app_network_image/'],
    ),
    BannedApi(
      id: 'material_icons',
      portable: true,
      label: 'Icons.x (Material / Cupertino icons)',
      replacement: 'an SVG via SvgPicture.asset(AppAssets.x)',
      types: {'Icons', 'CupertinoIcons'},
    ),
    BannedApi(
      id: 'linear_progress',
      label: 'LinearProgressIndicator',
      replacement: 'AppProgressBar',
      types: {'LinearProgressIndicator'},
      owners: ['$_kit/stats/app_progress_bar/', '$_kit/stats/app_segment_bar/', '$_kit/stats/app_bar_list_row/'],
    ),
    BannedApi(
      id: 'circular_progress',
      label: 'CircularProgressIndicator',
      replacement:
          'a skeleton (the piece\'s own, SkeletonBox, CardListSkeleton, ...), AppSpinner, or CustomButton(isLoading:)',
      types: {'CircularProgressIndicator', 'CupertinoActivityIndicator'},
      owners: ['$_kit/app_spinner/', '$_kit/custom_button/'],
    ),
    BannedApi(
      id: 'date_pickers',
      label: 'showDatePicker / showTimePicker / showDateRangePicker',
      replacement: 'AppDatePicker / AppDateRangePicker / AppTimeRangePicker',
      functions: {'showDatePicker', 'showTimePicker', 'showDateRangePicker'},
      owners: ['$_kit/app_date_picker/', '$_kit/app_date_range_picker/', '$_kit/app_time_range_picker/'],
    ),
    BannedApi(
      id: 'calendar_date_picker',
      label: 'CalendarDatePicker',
      replacement: 'AppDatePicker / AppDateRangePicker',
      types: {'CalendarDatePicker', 'DatePickerDialog', 'DateRangePickerDialog', 'TimePickerDialog'},
      owners: ['$_kit/app_date_picker/', '$_kit/app_date_range_picker/', '$_kit/app_time_range_picker/'],
    ),
    BannedApi(
      id: 'stepper',
      label: 'Stepper',
      replacement: 'AppNumberedSteps (minus / value / plus: AppStepper)',
      types: {'Stepper'},
      owners: ['$_kit/app_numbered_steps/', '$_kit/app_stepper/'],
    ),
    BannedApi(
      id: 'data_table',
      label: 'DataTable / Table',
      replacement: 'AppDataTable',
      types: {'DataTable', 'PaginatedDataTable', 'Table'},
      owners: ['$_kit/stats/app_data_table/'],
    ),
    BannedApi(
      id: 'fl_chart',
      label: 'package:fl_chart outside the stats kit',
      replacement: 'the stats kit (AppAreaChart, AppBarChart, AppDonutChart, ...)',
      package: 'fl_chart',
      types: {'*'},
      bansImport: true,
      owners: ['$_kit/stats/'],
    ),
    BannedApi(
      id: 'snack_bar',
      portable: true,
      label: 'SnackBar / ScaffoldMessenger',
      replacement: 'AlertCubit (called from the cubit)',
      types: {'SnackBar', 'ScaffoldMessenger'},
    ),
    BannedApi(
      id: 'show_dialog',
      label: 'showDialog / showModalBottomSheet / showGeneralDialog',
      replacement: 'Utils.openModalBottomSheet in a void show* opener',
      functions: {
        'showDialog',
        'showModalBottomSheet',
        'showGeneralDialog',
        'showAdaptiveDialog',
        'showCupertinoDialog',
        'showCupertinoModalPopup',
        'showBottomSheet',
      },
      owners: ['utils/utils.dart'],
    ),
    BannedApi(
      id: 'dialogs',
      label: 'AlertDialog / Dialog / SimpleDialog / BottomSheet',
      replacement: 'AppDialog / AppDialogHeader / AppDialogActions',
      types: {'AlertDialog', 'Dialog', 'SimpleDialog', 'BottomSheet', 'CupertinoAlertDialog'},
      owners: ['$_kit/app_dialog/', 'utils/utils.dart'],
    ),
    BannedApi(
      id: 'scaffold',
      label: 'Scaffold / AppBar outside a template',
      replacement: 'a template (AppContentPage, AdminLayout, AppEditorScaffold)',
      types: {'Scaffold', 'AppBar', 'SliverAppBar'},
      owners: ['$_kit/app_content_page/'],
      ownerCategory: 'Template',
    ),
    BannedApi(
      id: 'safe_area',
      label: 'SafeArea',
      replacement: 'AppSafeArea',
      types: {'SafeArea'},
      owners: ['$_kit/app_safe_area/'],
    ),
    BannedApi(
      id: 'navigation',
      label: 'NavigationRail / TabBar / Drawer',
      replacement: 'AppSectionNavRail / AppSectionNavStrip / AdminLayout',
      types: {'NavigationRail', 'TabBar', 'TabBarView', 'Drawer', 'NavigationDrawer'},
      owners: ['$_kit/app_section_nav_rail/', '$_kit/admin_layout/'],
    ),
    BannedApi(
      id: 'reorderable_list',
      label: 'ReorderableListView',
      replacement: 'AppReorderableList / AppReorderableTileGrid',
      types: {'ReorderableListView'},
      owners: ['$_kit/app_reorderable_list/', '$_kit/app_reorderable_tile_grid/'],
    ),
  ];

  @override
  List<BannedApi> get table => rows;

  @override
  List<BannedApi> tableFor(RuleLayout layout) => [for (final row in rows) resolve(row, layout)];

  /// [row] in the app of [layout]: its `kit:` entry, else the admin kit (the
  /// `admin` preset, or a package without a config) or a portable row as
  /// written, else a row that asks for the missing kit widget.
  static BannedApi resolve(BannedApi row, RuleLayout layout) {
    final own = layout.kit[row.id];
    if (own != null) {
      return row.withReplacement(own.use, [
        for (final owner in own.owners) owner.startsWith('lib/') ? owner.substring('lib/'.length) : owner,
      ]);
    }
    final preset = layout.preset;
    if (preset == null || preset == 'admin' || row.portable) return row;
    return row.withReplacement(
      "this app's kit widget for it; there is none yet: add it to lib/global_widgets "
      'and declare it in neon_check.yaml under `kit: ${row.id}: {use: <Widget>, owners: [<its folder>]}`',
      const [],
    );
  }

  @override
  DiagnosticCode get diagnosticCode => code;
}
