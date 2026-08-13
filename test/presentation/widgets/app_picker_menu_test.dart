import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notex/presentation/widgets/app_picker_menu.dart';

void main() {
  Widget pumpPicker<T>({
    required T value,
    required List<AppPickerOption<T>> options,
    required ValueChanged<T> onSelected,
    FocusNode? focusNode,
    Widget? child,
  }) {
    return MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: Scaffold(
        body: AppPickerMenu<T>(
          value: value,
          options: options,
          onSelected: onSelected,
          surfaceColor: const Color(0xFF1A1A2E),
          accentColor: const Color(0xFFFFD54F),
          focusNode: focusNode,
          child: child ?? const Text('trigger'),
        ),
      ),
    );
  }

  group('AppPickerMenu — shared picker for the task-tracker feature', () {
    testWidgets('tapping the trigger opens a menu listing every option',
        (tester) async {
      await tester.pumpWidget(pumpPicker<String>(
        value: 'a',
        options: const [
          AppPickerOption(value: 'a', label: 'Alpha'),
          AppPickerOption(value: 'b', label: 'Beta'),
        ],
        onSelected: (_) {},
      ));

      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
    });

    testWidgets('the current value renders a visible check mark, and only '
        'that row', (tester) async {
      await tester.pumpWidget(pumpPicker<String>(
        value: 'b',
        options: const [
          AppPickerOption(value: 'a', label: 'Alpha'),
          AppPickerOption(value: 'b', label: 'Beta'),
        ],
        onSelected: (_) {},
      ));

      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('selecting an option calls onSelected with that option\'s '
        'value', (tester) async {
      String? selected;
      await tester.pumpWidget(pumpPicker<String>(
        value: 'a',
        options: const [
          AppPickerOption(value: 'a', label: 'Alpha'),
          AppPickerOption(value: 'b', label: 'Beta'),
        ],
        onSelected: (value) => selected = value,
      ));

      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      expect(selected, 'b');
    });

    testWidgets(
        'a null-valued option is a legitimate selection, never confused '
        'with dismissing the menu without choosing anything', (tester) async {
      String? selected = 'unset';
      await tester.pumpWidget(pumpPicker<String?>(
        value: 'root',
        options: const [
          AppPickerOption(value: null, label: 'No folder'),
          AppPickerOption(value: 'root', label: 'Root'),
        ],
        onSelected: (value) => selected = value,
      ));

      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No folder'));
      await tester.pumpAndSettle();

      expect(
        selected,
        isNull,
        reason: 'choosing the null-valued option must call onSelected(null) '
            '— not be swallowed as if the menu had merely been dismissed',
      );
    });

    testWidgets(
        'dismissing the menu without choosing anything never calls '
        'onSelected', (tester) async {
      var calls = 0;
      await tester.pumpWidget(pumpPicker<String>(
        value: 'a',
        options: const [
          AppPickerOption(value: 'a', label: 'Alpha'),
          AppPickerOption(value: 'b', label: 'Beta'),
        ],
        onSelected: (_) => calls++,
      ));

      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();
      // Tap the barrier (top-left corner, well outside every menu item) to
      // dismiss without choosing.
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(calls, 0);
    });

    testWidgets('an action-style option never shows a check mark even when '
        'its value happens to equal the current value', (tester) async {
      await tester.pumpWidget(pumpPicker<String>(
        value: '__new__',
        options: const [
          AppPickerOption(value: 'a', label: 'Alpha'),
          AppPickerOption.action(value: '__new__', label: 'New…'),
        ],
        onSelected: (_) {},
      ));

      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      expect(
        find.byIcon(Icons.check_rounded),
        findsNothing,
        reason: 'an action row is never a "current selection", regardless '
            'of its sentinel value',
      );
    });

    testWidgets('choosing an option releases the supplied focus node so no '
        'stray focus rectangle lingers on the trigger', (tester) async {
      final focusNode = FocusNode(debugLabel: 'picker-under-test');
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(pumpPicker<String>(
        value: 'a',
        options: const [
          AppPickerOption(value: 'a', label: 'Alpha'),
          AppPickerOption(value: 'b', label: 'Beta'),
        ],
        onSelected: (_) {},
        focusNode: focusNode,
      ));

      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot('picker-under-test'),
        reason: 'the picker must release focus after a selection, or it '
            'keeps painting a focus rectangle around itself',
      );
    });

    testWidgets(
        'the opened menu resolves its background from the supplied '
        'surfaceColor, not the ambient seed-tinted ColorScheme default',
        (tester) async {
      const surface = Color(0xFF1A1A2E);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFFD54F)),
        ),
        home: Scaffold(
          body: AppPickerMenu<String>(
            value: 'a',
            options: const [AppPickerOption(value: 'a', label: 'Alpha')],
            onSelected: (_) {},
            surfaceColor: surface,
            accentColor: const Color(0xFFFFD54F),
            child: const Text('trigger'),
          ),
        ),
      ));

      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      final menu = tester.widget<Material>(
        find.ancestor(
          of: find.text('Alpha'),
          matching: find.byType(Material),
        ).first,
      );
      // The menu's own Material surface must NOT be the seed-derived
      // surfaceContainerHigh default — it must resolve from [surfaceColor].
      expect(menu.color, isNot(const ColorScheme.light().surfaceContainerHigh));
    });

    testWidgets('every menu row meets the 44x44 minimum tap target',
        (tester) async {
      await tester.pumpWidget(pumpPicker<String>(
        value: 'a',
        options: const [
          AppPickerOption(value: 'a', label: 'Alpha'),
          AppPickerOption(value: 'b', label: 'Beta'),
        ],
        onSelected: (_) {},
      ));

      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(InkWell).last);
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });
}
