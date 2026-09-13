import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:page_flip/page_flip.dart' show PageFlipEffect;

class LivePageFlipController {
  _LivePageFlipState? _state;
  void goToPage(int index) => _state?._goToPage(index);
}

/// Retains page_flip's curl painter, but never displays cached text at rest.
/// Only the visible page and its neighbour are mounted; snapshots exist solely
/// for the gesture/animation and are captured at the display's pixel ratio.
class LivePageFlip extends StatefulWidget {
  const LivePageFlip({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
    required this.initialIndex,
    required this.color,
    required this.onPageFlipped,
    this.gesturesEnabled = true,
  });
  final LivePageFlipController controller;
  final int itemCount, initialIndex;
  final IndexedWidgetBuilder itemBuilder;
  final Color color;
  final ValueChanged<int> onPageFlipped;
  final bool gesturesEnabled;
  @override
  State<LivePageFlip> createState() => _LivePageFlipState();
}

class _LivePageFlipState extends State<LivePageFlip>
    with SingleTickerProviderStateMixin {
  final _boundary = GlobalKey();
  late final AnimationController _curl;
  late int _index;
  int? _target;
  int? _pendingIndex;
  ui.Image? _image;
  Future<void>? _capturing;
  double _drag = 0;
  bool _dragging = false, _finishing = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _curl = AnimationController(
      vsync: this,
      value: 1,
      duration: const Duration(milliseconds: 420),
    );
    widget.controller._state = this;
  }

  void _goToPage(int index) {
    if (index < 0 || index >= widget.itemCount) return;
    if (index == _index) return;
    if (_target != null || _capturing != null || _finishing) {
      if (index != _target) _pendingIndex = index;
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _index = index);
      return;
    }
    unawaited(_automaticTurn(index));
  }

  Future<void> _capture(int target) async {
    if (_capturing != null || _target != null) return;
    final future = () async {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary = _boundary.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) return;
      final snapshot = await boundary.toImage(
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
      if (!mounted) {
        snapshot.dispose();
        return;
      }
      setState(() {
        _image = snapshot;
        _target = target;
      });
    }();
    _capturing = future;
    try {
      await future;
    } finally {
      _capturing = null;
    }
  }

  Future<void> _automaticTurn(int target) async {
    await _capture(target);
    if (mounted && _target != null) await _finish(true, notify: false);
  }

  Future<void> _finish(bool commit, {bool notify = true}) async {
    if (_finishing) return;
    _finishing = true;
    try {
      await _capturing;
      if (!mounted || _target == null) return;
      await _curl.animateTo(commit ? 0 : 1, curve: Curves.easeOutCubic);
      if (!mounted) return;
      final target = _target!;
      final image = _image;
      setState(() {
        if (commit) _index = target;
        _target = null;
        _image = null;
        _curl.value = 1;
      });
      image?.dispose();
      if (commit && notify) widget.onPageFlipped(target);
    } finally {
      _finishing = false;
      if (mounted && _pendingIndex != null) {
        final pending = _pendingIndex!;
        _pendingIndex = null;
        _goToPage(pending);
      }
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      return GestureDetector(
        onHorizontalDragStart:
            !widget.gesturesEnabled
                ? null
                : (_) {
                  if (_finishing || _target != null) return;
                  _dragging = true;
                  _drag = 0;
                },
        onHorizontalDragUpdate:
            !widget.gesturesEnabled
                ? null
                : (details) {
                  if (!_dragging || _finishing) return;
                  _drag += details.delta.dx;
                  if (_target == null &&
                      _capturing == null &&
                      _drag.abs() > 8) {
                    final target = _index + (_drag < 0 ? 1 : -1);
                    if (target < 0 || target >= widget.itemCount) return;
                    if (MediaQuery.disableAnimationsOf(context)) return;
                    unawaited(_capture(target));
                  }
                  if (_target != null) {
                    _curl.value = (1 - _drag.abs() / constraints.maxWidth)
                        .clamp(0.0, 1.0);
                  }
                },
        onHorizontalDragEnd:
            !widget.gesturesEnabled
                ? null
                : (details) {
                  if (!_dragging) return;
                  _dragging = false;
                  final commit =
                      _drag.abs() > constraints.maxWidth * .2 ||
                      details.velocity.pixelsPerSecond.dx.abs() > 450;
                  if (MediaQuery.disableAnimationsOf(context)) {
                    final target = _index + (_drag < 0 ? 1 : -1);
                    if (commit && target >= 0 && target < widget.itemCount) {
                      setState(() => _index = target);
                      widget.onPageFlipped(target);
                    }
                  } else {
                    unawaited(_finish(commit));
                  }
                },
        onHorizontalDragCancel: () {
          _dragging = false;
          unawaited(_finish(false));
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              key: _boundary,
              child: KeyedSubtree(
                key: ValueKey(_target ?? _index),
                child: widget.itemBuilder(context, _target ?? _index),
              ),
            ),
            if (_image != null)
              IgnorePointer(
                child: CustomPaint(
                  painter: PageFlipEffect(
                    amount: _curl,
                    image: _image!,
                    backgroundColor: widget.color,
                    isRightSwipe: _target! < _index,
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );

  @override
  void dispose() {
    if (identical(widget.controller._state, this)) {
      widget.controller._state = null;
    }
    _curl.dispose();
    _image?.dispose();
    super.dispose();
  }
}
