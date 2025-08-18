// lib/widgets/cupertino_fixed_item_mouse_scrolling.dart
import 'dart:collection';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';

/// A scroll wrapper that:
///  - allows all pointer devices to drag (CupertinoAnyDeviceScrollBehavior)
///  - intercepts pointer scroll (mouse wheel / touchpad) and moves the
///    FixedExtentScrollController by single-item increments but only when
///    an accumulated delta passes a sensitivity threshold.
///  - this reduces the insanely fast touchpad scrolling on desktop/web.
///
/// Usage:
/// Wrap the `CupertinoPicker` (or any picker using a FixedExtentScrollController)
/// child with this widget and pass the controller you give to the picker.
class CupertinoFixedItemMouseScrolling extends StatefulWidget {
  const CupertinoFixedItemMouseScrolling({
    required this.scrollController,
    required this.child,
    super.key,
    // threshold in logical pixels. Increase to make scrolling slower (more
    // accumulation needed before a step happens).
    this.scrollThreshold = 60.0,
  });

  final FixedExtentScrollController? scrollController;
  final Widget child;
  final double scrollThreshold;

  @override
  State<CupertinoFixedItemMouseScrolling> createState() =>
      _CupertinoFixedItemMouseScrollingState();
}

class _CupertinoFixedItemMouseScrollingState
    extends State<CupertinoFixedItemMouseScrolling> {
  // Keeps per-controller accumulated deltas (support multiple controllers
  // if same widget is reused).
  final Map<int, double> _accumulators = HashMap<int, double>();

  double _accForController(FixedExtentScrollController controller) {
    return _accumulators[controller.hashCode] ?? 0.0;
  }

  void _setAccForController(FixedExtentScrollController controller, double v) {
    _accumulators[controller.hashCode] = v;
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: const _CupertinoAnyDeviceScrollBehavior(),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerSignal: (PointerSignalEvent event) {
          // handle only wheel/touchpad pointer scroll
          if (event is! PointerScrollEvent) return;

          final controller = widget.scrollController;
          if (controller == null || !controller.hasClients) return;
          if (controller.positions.length != 1) return;

          // accumulate delta (we only care about vertical wheel movement).
          // positive dy -> scroll down (increase index)
          double accum = _accForController(controller);
          accum += event.scrollDelta.dy;

          final threshold = widget.scrollThreshold.abs();
          final int steps = (accum.abs() / threshold).floor();

          if (steps == 0) {
            // Not enough delta to trigger an item step yet. Store and return.
            _setAccForController(controller, accum);
            return;
          }

          // For each step, move exactly one item in the intended direction.
          // Use the 'jumpToItem' first to set the logical selection, then
          // try to counteract default pointerScroll side effect as in the
          // original workaround.
          for (int i = 0; i < steps; i++) {
            // defensive read
            final int current = controller.selectedItem;
            final int newIndex =
                accum > 0 ? (current + 1) : (current - 1);

            // Prevent out-of-range: clamp between 0 and itemCount-1 if known.
            // We don't know itemCount here; assume picker will ignore invalid values.
            try {
              controller.jumpToItem(newIndex);
            } catch (_) {
              // ignore possible errors from invalid range
            }

            // Workaround (original): make a tiny correct-offset and then
            // counteract the forthcoming pointerScroll delta to avoid big jumps.
            final double? correctOffset = controller.offset + 0.001;
            try {
              // attempt to counteract default pointerScroll
              controller.jumpTo(controller.offset - event.scrollDelta.dy);
            } catch (_) {
              // ignore
            }
            // ensure final correct offset next frame
            SchedulerBinding.instance.addPostFrameCallback((_) {
              try {
                if (correctOffset != null) controller.jumpTo(correctOffset);
              } catch (_) {}
            });
          }

          // subtract processed amount, keep remainder
          final double consumed = steps * threshold * (accum.sign);
          accum = accum - consumed;
          _setAccForController(controller, accum);
        },
        child: widget.child,
      ),
    );
  }

  @override
  void dispose() {
    _accumulators.clear();
    super.dispose();
  }
}

/// Enables any pointer device dragging (mouse drag, touchpad, touch).
class _CupertinoAnyDeviceScrollBehavior extends CupertinoScrollBehavior {
  const _CupertinoAnyDeviceScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
        ...PointerDeviceKind.values,
      };
}
