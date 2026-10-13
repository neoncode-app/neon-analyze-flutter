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
      owners: ['$_kit/rounded_container/'],
    ),
    BannedApi(
      label: 'DecoratedBox / Card / ClipRRect',
      replacement: 'RoundedContainer / RoundedContainer.card (clipBehavior for clipping)',
      types: {'DecoratedBox', 'Card', 'ClipRRect'},
      owners: ['$_kit/rounded_container/'],
    ),
    BannedApi(
      label: 'GestureDetector',
      replacement: 'AppTapArea (tap / long press / pan without a look) or RoundedContainer(onTap:) (with a ripple)',
      types: {'GestureDetector'},
      owners: ['$_kit/app_tap_area/'],
    ),
    BannedApi(
      label: 'InkWell / InkResponse',
      replacement: 'RoundedContainer(onTap:), or AppMaterialSurface(onTap:) on an elevated surface',
      types: {'InkWell', 'InkResponse'},
      owners: ['$_kit/rounded_container/', '$_kit/custom_button/', '$_kit/app_material_surface/'],
    ),
    BannedApi(
      label: 'Material',
      replacement: 'AppMaterialSurface (an ink host, an elevated surface) or RoundedContainer(onTap:)',
      types: {'Material'},
      owners: ['$_kit/app_material_surface/', '$_kit/rounded_container/', '$_kit/custom_button/'],
    ),
    BannedApi(
      label: 'MouseRegion for hover or a cursor',
      replacement:
          'AppTapArea (onHoverChanged / cursor) or RoundedContainer(onTap:) with hoverColor / hoverBorderColor',
      types: {'MouseRegion'},
      owners: ['$_kit/app_tap_area/', '$_kit/rounded_container/', '$_kit/custom_button/'],
    ),
    BannedApi(
      label: 'TextButton / OutlinedButton / ElevatedButton / FilledButton',
      replacement: 'CustomButton',
      types: {'TextButton', 'OutlinedButton', 'ElevatedButton', 'FilledButton', 'MaterialButton', 'CupertinoButton'},
      // The theme styles Material buttons for ThemeData (`*.styleFrom`).
      owners: ['$_kit/custom_button/', 'utils/ui/app_style.dart', 'utils/ui/theme/'],
    ),
    BannedApi(
      label: 'IconButton / FloatingActionButton',
      replacement: 'CustomButton.icon / CustomButton.tonalIcon',
      types: {'IconButton', 'FloatingActionButton'},
      owners: ['$_kit/custom_button/'],
    ),
    BannedApi(
      label: 'Switch / SwitchListTile',
      replacement: 'AppSwitch / AppSwitchRow',
      types: {'Switch', 'SwitchListTile', 'CupertinoSwitch'},
      owners: ['$_kit/app_switch/', '$_kit/app_switch_row/'],
    ),
    BannedApi(
      label: 'Checkbox / CheckboxListTile',
      replacement: 'AppCheckbox / AppCheckboxRow',
      types: {'Checkbox', 'CheckboxListTile'},
      owners: ['$_kit/app_checkbox/', '$_kit/app_checkbox_row/'],
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
      owners: ['$_kit/app_choice_pills/', '$_kit/app_segmented_control/', '$_kit/app_binary_toggle/'],
    ),
    BannedApi(
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
      label: 'DropdownButton / DropdownMenu',
      replacement: 'AppDropdownMenu / AppLabeledDropdown',
      types: {'DropdownButton', 'DropdownButtonFormField', 'DropdownMenu'},
      owners: ['$_kit/app_dropdown_menu/', '$_kit/app_labeled_dropdown/'],
    ),
    BannedApi(
      label: 'Chip / Badge',
      replacement: 'AppPill / AppNumberBadge / NotificationCountBadge',
      types: {'Chip', 'InputChip', 'ActionChip', 'RawChip', 'Badge'},
      owners: ['$_kit/app_pill/', '$_kit/app_number_badge/', '$_kit/notification_count_badge/'],
    ),
    BannedApi(
      label: 'Divider / VerticalDivider',
      replacement: 'AppDivider / ShadowDivider',
      types: {'Divider', 'VerticalDivider'},
      owners: ['$_kit/app_divider/', '$_kit/shadow_divider/'],
    ),
    BannedApi(
      label: 'ExpansionTile',
      replacement: 'AppExpansionTile',
      types: {'ExpansionTile'},
      owners: ['$_kit/app_expansion_tile/'],
    ),
    BannedApi(
      label: 'ListTile',
      replacement: 'AppListRow / AppPersonRow / AppKeyValueRow',
      types: {'ListTile'},
      owners: ['$_kit/app_list_row/', '$_kit/app_person_row/', '$_kit/app_key_value_row/'],
    ),
    BannedApi(
      label: 'CircleAvatar',
      replacement: 'AppAvatar',
      types: {'CircleAvatar'},
      owners: ['$_kit/app_avatar/'],
    ),
    BannedApi(
      label: 'Image.network',
      replacement: 'AppNetworkImage',
      types: {'Image'},
      constructors: {'network'},
      owners: ['$_kit/app_network_image/'],
    ),
    BannedApi(
      label: 'NetworkImage',
      replacement: 'AppNetworkImage',
      types: {'NetworkImage'},
      owners: ['$_kit/app_network_image/'],
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
      owners: ['$_kit/stats/app_progress_bar/', '$_kit/stats/app_segment_bar/', '$_kit/stats/app_bar_list_row/'],
    ),
    BannedApi(
      label: 'CircularProgressIndicator',
      replacement:
          'a skeleton (the piece\'s own, SkeletonBox, CardListSkeleton, ...), AppSpinner, or CustomButton(isLoading:)',
      types: {'CircularProgressIndicator', 'CupertinoActivityIndicator'},
      owners: ['$_kit/app_spinner/', '$_kit/custom_button/'],
    ),
    BannedApi(
      label: 'showDatePicker / showTimePicker / showDateRangePicker',
      replacement: 'AppDatePicker / AppDateRangePicker / AppTimeRangePicker',
      functions: {'showDatePicker', 'showTimePicker', 'showDateRangePicker'},
      owners: ['$_kit/app_date_picker/', '$_kit/app_date_range_picker/', '$_kit/app_time_range_picker/'],
    ),
    BannedApi(
      label: 'CalendarDatePicker',
      replacement: 'AppDatePicker / AppDateRangePicker',
      types: {'CalendarDatePicker', 'DatePickerDialog', 'DateRangePickerDialog', 'TimePickerDialog'},
      owners: ['$_kit/app_date_picker/', '$_kit/app_date_range_picker/', '$_kit/app_time_range_picker/'],
    ),
    BannedApi(
      label: 'Stepper',
      replacement: 'AppNumberedSteps (minus / value / plus: AppStepper)',
      types: {'Stepper'},
      owners: ['$_kit/app_numbered_steps/', '$_kit/app_stepper/'],
    ),
    BannedApi(
      label: 'DataTable / Table',
      replacement: 'AppDataTable',
      types: {'DataTable', 'PaginatedDataTable', 'Table'},
      owners: ['$_kit/stats/app_data_table/'],
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
      owners: ['$_kit/app_copy_field/', '$_kit/app_copy_button/'],
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
      owners: ['$_kit/app_dialog/', 'utils/utils.dart'],
    ),
    BannedApi(
      label: 'Scaffold / AppBar outside a template',
      replacement: 'a template (AppContentPage, AdminLayout, AppEditorScaffold)',
      types: {'Scaffold', 'AppBar', 'SliverAppBar'},
      owners: ['$_kit/app_content_page/'],
      ownerCategory: 'Template',
    ),
    BannedApi(
      label: 'SafeArea',
      replacement: 'AppSafeArea',
      types: {'SafeArea'},
      owners: ['$_kit/app_safe_area/'],
    ),
    BannedApi(
      label: 'NavigationRail / TabBar / Drawer',
      replacement: 'AppSectionNavRail / AppSectionNavStrip / AdminLayout',
      types: {'NavigationRail', 'TabBar', 'TabBarView', 'Drawer', 'NavigationDrawer'},
      owners: ['$_kit/app_section_nav_rail/', '$_kit/admin_layout/'],
    ),
    BannedApi(
      label: 'ReorderableListView',
      replacement: 'AppReorderableList / AppReorderableTileGrid',
      types: {'ReorderableListView'},
      owners: ['$_kit/app_reorderable_list/', '$_kit/app_reorderable_tile_grid/'],
    ),
  ];

  @override
  List<BannedApi> get table => rows;

  @override
  DiagnosticCode get diagnosticCode => code;
}
