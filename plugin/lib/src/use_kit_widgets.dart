import 'package:analyzer/error/error.dart';

import 'package:neon_lints/src/banned_api/banned_api.dart';

/// Bans raw Flutter (and `intl` / `fl_chart`) APIs that the admin widget kit
/// replaces, and names the kit widget to use instead.
///
/// The table below is the whole rule: one [BannedApi] row per banned API,
/// with its replacement and the kit files that own it (they implement the
/// replacement, so they may still use the raw API). Adding a ban is one row.
/// Owner paths are relative to `lib/` and follow the neoncode kit layout,
/// which is why the rule is opt-in (`registerLintRule`) per app.
///
/// Source of the table: ticket NCR0000014, "Kit components instead of raw
/// Flutter".
class UseKitWidgets extends BannedApiRule {
  UseKitWidgets() : super(name: 'use_kit_widgets', description: _desc);

  static const _desc = 'Use the admin widget kit instead of raw Flutter widgets.';

  static final LintCode code = bannedApiCode('use_kit_widgets', what: 'raw Flutter that the widget kit replaces');

  static const _kit = 'global_widgets/global';

  static const rows = <BannedApi>[
    BannedApi(
      label: 'Container(decoration:)',
      replacement: 'RoundedContainer / RoundedContainer.card',
      types: {'Container'},
      onlyWithArgs: {'decoration', 'foregroundDecoration'},
      owners: ['$_kit/rounded_container.dart'],
    ),
    BannedApi(
      label: 'DecoratedBox / Card / ClipRRect',
      replacement: 'RoundedContainer / RoundedContainer.card (clipBehavior for clipping)',
      types: {'DecoratedBox', 'Card', 'ClipRRect'},
      owners: ['$_kit/rounded_container.dart'],
    ),
    BannedApi(
      label: 'GestureDetector',
      replacement: 'AppTapArea (tap / long press / pan without a look) or RoundedContainer(onTap:) (with a ripple)',
      types: {'GestureDetector'},
      owners: ['$_kit/app_tap_area.dart'],
    ),
    BannedApi(
      label: 'InkWell / InkResponse',
      replacement: 'RoundedContainer(onTap:), or AppMaterialSurface(onTap:) on an elevated surface',
      types: {'InkWell', 'InkResponse'},
      owners: ['$_kit/rounded_container.dart', '$_kit/custom_button.dart', '$_kit/app_material_surface.dart'],
    ),
    BannedApi(
      label: 'Material',
      replacement: 'AppMaterialSurface (an ink host, an elevated surface) or RoundedContainer(onTap:)',
      types: {'Material'},
      owners: ['$_kit/app_material_surface.dart', '$_kit/rounded_container.dart', '$_kit/custom_button.dart'],
    ),
    BannedApi(
      label: 'MouseRegion for hover or a cursor',
      replacement:
          'AppTapArea (onHoverChanged / cursor) or RoundedContainer(onTap:) with hoverColor / hoverBorderColor',
      types: {'MouseRegion'},
      owners: ['$_kit/app_tap_area.dart', '$_kit/rounded_container.dart', '$_kit/custom_button.dart'],
    ),
    BannedApi(
      label: 'TextButton / OutlinedButton / ElevatedButton / FilledButton',
      replacement: 'CustomButton',
      types: {'TextButton', 'OutlinedButton', 'ElevatedButton', 'FilledButton', 'MaterialButton', 'CupertinoButton'},
      // The theme styles Material buttons for ThemeData (`*.styleFrom`).
      owners: ['$_kit/custom_button.dart', 'utils/ui/app_style.dart', 'utils/ui/theme/'],
    ),
    BannedApi(
      label: 'IconButton / FloatingActionButton',
      replacement: 'CustomButton.icon / CustomButton.tonalIcon',
      types: {'IconButton', 'FloatingActionButton'},
      owners: ['$_kit/custom_button.dart'],
    ),
    BannedApi(
      label: 'Switch / SwitchListTile',
      replacement: 'AppSwitch / AppSwitchRow',
      types: {'Switch', 'SwitchListTile', 'CupertinoSwitch'},
      owners: ['$_kit/app_switch.dart'],
    ),
    BannedApi(
      label: 'Checkbox / CheckboxListTile',
      replacement: 'AppCheckbox / AppCheckboxRow',
      types: {'Checkbox', 'CheckboxListTile'},
      owners: ['$_kit/app_checkbox.dart'],
    ),
    BannedApi(
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
      owners: ['$_kit/app_choice_pills.dart', '$_kit/app_segmented_control.dart', '$_kit/app_binary_toggle.dart'],
    ),
    BannedApi(
      label: 'TextField / TextFormField',
      replacement: 'AppTextField / AppSearchField / AppCodeInput / AppInlineTimeField',
      types: {'TextField', 'TextFormField', 'CupertinoTextField'},
      owners: [
        '$_kit/app_text_field.dart',
        '$_kit/app_search_field.dart',
        '$_kit/app_code_input.dart',
        '$_kit/app_inline_time_field.dart',
      ],
    ),
    BannedApi(
      label: 'DropdownButton / DropdownMenu',
      replacement: 'AppDropdownMenu / AppLabeledDropdown',
      types: {'DropdownButton', 'DropdownButtonFormField', 'DropdownMenu'},
      owners: ['$_kit/app_dropdown_menu.dart', '$_kit/app_labeled_dropdown.dart'],
    ),
    BannedApi(
      label: 'Chip / Badge',
      replacement: 'AppPill / AppNumberBadge / NotificationCountBadge',
      types: {'Chip', 'InputChip', 'ActionChip', 'RawChip', 'Badge'},
      owners: ['$_kit/app_pill.dart', '$_kit/app_number_badge.dart', '$_kit/notification_count_badge.dart'],
    ),
    BannedApi(
      label: 'Divider / VerticalDivider',
      replacement: 'AppDivider / ShadowDivider',
      types: {'Divider', 'VerticalDivider'},
      owners: ['$_kit/app_divider.dart', '$_kit/shadow_divider.dart'],
    ),
    BannedApi(
      label: 'ExpansionTile',
      replacement: 'AppExpansionTile',
      types: {'ExpansionTile'},
      owners: ['$_kit/app_expansion_tile.dart'],
    ),
    BannedApi(
      label: 'ListTile',
      replacement: 'AppListRow / AppPersonRow / AppKeyValueRow',
      types: {'ListTile'},
      owners: ['$_kit/app_list_row.dart', '$_kit/app_person_row.dart', '$_kit/app_key_value_row.dart'],
    ),
    BannedApi(
      label: 'CircleAvatar',
      replacement: 'AppAvatar',
      types: {'CircleAvatar'},
      owners: ['$_kit/app_avatar.dart'],
    ),
    BannedApi(
      label: 'Image.network',
      replacement: 'AppNetworkImage',
      types: {'Image'},
      constructors: {'network'},
      owners: ['$_kit/app_network_image.dart'],
    ),
    BannedApi(
      label: 'NetworkImage',
      replacement: 'AppNetworkImage',
      types: {'NetworkImage'},
      owners: ['$_kit/app_network_image.dart'],
    ),
    BannedApi(
      label: 'Icons.x (Material / Cupertino icons)',
      replacement: 'an SVG via SvgPicture.asset(AppAssets.x)',
      types: {'Icons', 'CupertinoIcons'},
    ),
    BannedApi(
      label: 'LinearProgressIndicator',
      replacement: 'AppProgressBar',
      types: {'LinearProgressIndicator'},
      owners: ['$_kit/stats/app_progress_bar.dart'],
    ),
    BannedApi(
      label: 'CircularProgressIndicator',
      replacement:
          'a skeleton (the piece\'s own, SkeletonBox, CardListSkeleton, ...), AppSpinner, or CustomButton(isLoading:)',
      types: {'CircularProgressIndicator', 'CupertinoActivityIndicator'},
      owners: ['$_kit/app_spinner.dart', '$_kit/custom_button.dart'],
    ),
    BannedApi(
      label: 'showDatePicker / showTimePicker / showDateRangePicker',
      replacement: 'AppDatePicker / AppDateRangePicker / AppTimeRangePicker',
      functions: {'showDatePicker', 'showTimePicker', 'showDateRangePicker'},
      owners: ['$_kit/app_date_picker.dart', '$_kit/app_date_range_picker.dart', '$_kit/app_time_range_picker.dart'],
    ),
    BannedApi(
      label: 'CalendarDatePicker',
      replacement: 'AppDatePicker / AppDateRangePicker',
      types: {'CalendarDatePicker', 'DatePickerDialog', 'DateRangePickerDialog', 'TimePickerDialog'},
      owners: ['$_kit/app_date_picker.dart', '$_kit/app_date_range_picker.dart', '$_kit/app_time_range_picker.dart'],
    ),
    BannedApi(
      label: 'Stepper',
      replacement: 'AppNumberedSteps (minus / value / plus: AppStepper)',
      types: {'Stepper'},
      owners: ['$_kit/app_numbered_steps.dart', '$_kit/app_stepper.dart'],
    ),
    BannedApi(
      label: 'DataTable / Table',
      replacement: 'AppDataTable',
      types: {'DataTable', 'PaginatedDataTable', 'Table'},
      owners: ['$_kit/stats/app_data_table.dart'],
    ),
    BannedApi(
      label: 'package:fl_chart outside the stats kit',
      replacement: 'the stats kit (AppAreaChart, AppBarChart, AppDonutChart, ...)',
      package: 'fl_chart',
      types: {'*'},
      bansImport: true,
      owners: ['$_kit/stats/'],
    ),
    BannedApi(
      label: 'Clipboard',
      replacement: 'AppCopyField / AppCopyButton',
      types: {'Clipboard'},
      owners: ['$_kit/app_copy_field.dart'],
    ),
    BannedApi(
      label: 'SnackBar / ScaffoldMessenger',
      replacement: 'AlertCubit (called from the cubit)',
      types: {'SnackBar', 'ScaffoldMessenger'},
    ),
    BannedApi(
      label: 'DateFormat',
      replacement: 'formatAppDate / formatAppDateTime (lib/utils/helpers/app_format.dart)',
      package: 'intl',
      types: {'DateFormat'},
      owners: ['utils/helpers/app_format.dart'],
    ),
    BannedApi(
      label: 'showDialog / showModalBottomSheet / showGeneralDialog',
      replacement: 'Utils.showCustomModalBottomSheet',
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
      label: 'AlertDialog / Dialog / SimpleDialog / BottomSheet',
      replacement: 'AppDialog / AppDialogHeader / AppDialogActions',
      types: {'AlertDialog', 'Dialog', 'SimpleDialog', 'BottomSheet', 'CupertinoAlertDialog'},
      owners: ['$_kit/app_dialog.dart', 'utils/utils.dart'],
    ),
    BannedApi(
      label: 'Scaffold / AppBar outside a template',
      replacement: 'a template (AppContentPage, AdminLayout, AppEditorScaffold)',
      types: {'Scaffold', 'AppBar', 'SliverAppBar'},
      ownerCategory: 'Template',
    ),
    BannedApi(
      label: 'SafeArea',
      replacement: 'AppSafeArea',
      types: {'SafeArea'},
      owners: ['$_kit/app_safe_area.dart'],
    ),
    BannedApi(
      label: 'NavigationRail / TabBar / Drawer',
      replacement: 'AppSectionNavRail / AppSectionNavStrip / AdminLayout',
      types: {'NavigationRail', 'TabBar', 'TabBarView', 'Drawer', 'NavigationDrawer'},
      owners: ['$_kit/app_section_nav.dart', '$_kit/admin_layout.dart'],
    ),
    BannedApi(
      label: 'ReorderableListView',
      replacement: 'AppReorderableList / AppReorderableTileGrid',
      types: {'ReorderableListView'},
      owners: ['$_kit/app_reorderable_list.dart', '$_kit/app_reorderable_tile_grid.dart'],
    ),
  ];

  @override
  List<BannedApi> get table => rows;

  @override
  DiagnosticCode get diagnosticCode => code;
}
