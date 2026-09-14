import 'dart:math' as math;
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'design_system.dart';
import 'l10n.dart';

/// A user-facing capability state, distinct from a retryable translation error.
class SelectionTranslationUnavailable implements Exception {
  const SelectionTranslationUnavailable(this.message);
  final String message;
}

/// Keeps native selection/copy controls and adds an anchored, non-route popup.
/// OverlayPortal ties its lifetime to the passage: paging/disposal removes it.
class SelectionTranslationArea extends StatefulWidget {
  const SelectionTranslationArea({
    super.key,
    required this.child,
    required this.translate,
    required this.sourceLabel,
    required this.targetLabel,
    this.onSelectionActivityChanged,
  });
  final Widget child;
  final Future<String> Function(String text) translate;
  final String sourceLabel, targetLabel;
  final ValueChanged<bool>? onSelectionActivityChanged;
  @override
  State<SelectionTranslationArea> createState() =>
      _SelectionTranslationAreaState();
}

class _SelectionTranslationAreaState extends State<SelectionTranslationArea> {
  final _portal = OverlayPortalController();
  String _selection = '', _passage = '';
  Offset _above = Offset.zero, _below = Offset.zero;
  SelectableRegionState? _region;
  LocalHistoryEntry? _history;
  bool _active = false;

  void _notifySelection() {
    final active = _portal.isShowing || _selection.isNotEmpty;
    if (_active == active) return;
    _active = active;
    widget.onSelectionActivityChanged?.call(active);
  }

  void _show(SelectableRegionState region) {
    if (_portal.isShowing) return;
    final text = _selection.trim();
    if (text.isEmpty) return;
    final anchors = region.contextMenuAnchors;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final primary = overlay.globalToLocal(anchors.primaryAnchor);
    final secondary = overlay.globalToLocal(
      anchors.secondaryAnchor ?? anchors.primaryAnchor,
    );
    final centerX = (primary.dx + secondary.dx) / 2;
    _above = Offset(centerX, math.min(primary.dy, secondary.dy));
    _below = Offset(centerX, math.max(primary.dy, secondary.dy));
    _passage = text;
    _region = region;
    region.hideToolbar();
    _portal.show();
    _history = LocalHistoryEntry(
      onRemove: () {
        _history = null;
        _close();
      },
    );
    ModalRoute.of(context)?.addLocalHistoryEntry(_history!);
    _notifySelection();
  }

  void _close() {
    if (_portal.isShowing) _portal.hide();
    final history = _history;
    _history = null;
    history?.remove();
    if (_region?.mounted ?? false) _region!.clearSelection();
    _region = null;
    _selection = '';
    _notifySelection();
  }

  @override
  void dispose() {
    // The route clears a local-history entry when the route is disposed.
    if (_active) widget.onSelectionActivityChanged?.call(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _portal,
    overlayChildBuilder: (context) {
      final media = MediaQuery.of(context);
      return Positioned.fill(
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
          child: Focus(
            autofocus: true,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _close,
                    onPanStart: (_) => _close(),
                    excludeFromSemantics: true,
                    child: const ColoredBox(color: Colors.transparent),
                  ),
                ),
                CustomSingleChildLayout(
                  delegate: TranslationPopoverLayout(
                    above: _above,
                    below: _below,
                    insets: EdgeInsets.fromLTRB(
                      media.padding.left + 12,
                      media.padding.top + kToolbarHeight + 12,
                      media.padding.right + 12,
                      math.max(
                            media.padding.bottom + 84,
                            media.viewInsets.bottom,
                          ) +
                          12,
                    ),
                    preferredWidth:
                        (_passage.length > 140 ? 420 : 310) *
                        media.textScaler.scale(1).clamp(1, 1.3),
                  ),
                  child: _TranslationBubble(
                    text: _passage,
                    translate: widget.translate,
                    sourceLabel: widget.sourceLabel,
                    targetLabel: widget.targetLabel,
                    onClose: _close,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
    child: Builder(
      builder: (context) {
        final p = PaperColors.of(context);
        return TextSelectionTheme(
          data: TextSelectionThemeData(
            selectionColor: p.selection,
            selectionHandleColor: p.selectionHandle,
            cursorColor: p.selectionHandle,
          ),
          child: SelectionArea(
            onSelectionChanged: (content) {
              _selection = content?.plainText ?? '';
              _notifySelection();
            },
            contextMenuBuilder: (context, region) {
              // The selection handles remain native. Translation is immediate:
              // no extra action or modal step is required from the reader.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _selection.trim().isNotEmpty) _show(region);
              });
              return const SizedBox.shrink();
            },
            child: widget.child,
          ),
        );
      },
    ),
  );
}

/// Fits actual content above/below the selection, respecting notch, keyboard,
/// landscape and large text. Long selections get a scrollable bounded surface.
class TranslationPopoverLayout extends SingleChildLayoutDelegate {
  TranslationPopoverLayout({
    required this.above,
    required this.below,
    required this.insets,
    required this.preferredWidth,
  });
  final Offset above, below;
  final EdgeInsets insets;
  final double preferredWidth;
  Rect _safe(Size size) => Rect.fromLTRB(
    insets.left,
    insets.top,
    math.max(insets.left, size.width - insets.right),
    math.max(insets.top, size.height - insets.bottom),
  );
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final safe = _safe(constraints.biggest);
    final topRoom = (above.dy - 12 - safe.top).clamp(0.0, safe.height);
    final bottomRoom = (safe.bottom - below.dy - 12).clamp(0.0, safe.height);
    final room = topRoom >= bottomRoom ? topRoom : bottomRoom;
    final width = math.min(preferredWidth, safe.width);
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: math.min(480, math.max(120, room)),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final safe = _safe(size);
    final anchorX = (above.dx + below.dx) / 2;
    final x = (anchorX - childSize.width / 2).clamp(
      safe.left,
      safe.right - childSize.width,
    );
    final topRoom = (above.dy - 12 - safe.top).clamp(0.0, safe.height);
    final bottomRoom = (safe.bottom - below.dy - 12).clamp(0.0, safe.height);
    final double y;
    if (topRoom >= bottomRoom && childSize.height <= topRoom) {
      y = above.dy - 12 - childSize.height;
    } else if (childSize.height <= bottomRoom) {
      y = below.dy + 12;
    } else if (topRoom >= bottomRoom) {
      y = safe.top;
    } else {
      y = safe.bottom - childSize.height;
    }
    return Offset(x, y.clamp(safe.top, safe.bottom - childSize.height));
  }

  @override
  bool shouldRelayout(TranslationPopoverLayout oldDelegate) =>
      above != oldDelegate.above ||
      below != oldDelegate.below ||
      insets != oldDelegate.insets ||
      preferredWidth != oldDelegate.preferredWidth;
}

class _TranslationBubble extends StatefulWidget {
  const _TranslationBubble({
    required this.text,
    required this.translate,
    required this.sourceLabel,
    required this.targetLabel,
    required this.onClose,
  });
  final String text, sourceLabel, targetLabel;
  final Future<String> Function(String) translate;
  final VoidCallback onClose;
  @override
  State<_TranslationBubble> createState() => _TranslationBubbleState();
}

class _TranslationBubbleState extends State<_TranslationBubble> {
  late Future<String> _result;
  bool _copied = false;
  @override
  void initState() {
    super.initState();
    _result = Future.sync(() => widget.translate(widget.text));
  }

  @override
  Widget build(BuildContext context) {
    final p = PaperColors.of(context);
    return Semantics(
      container: true,
      label: 'Traduction du passage sélectionné'.tr(context),
      child: Material(
        key: const ValueKey('selection-translation-popover'),
        color: p.surface,
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: .2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: p.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: 18,
                right: 4,
                top: 4,
                bottom: 4,
              ),
              child: Row(
                children: [
                  Icon(Icons.translate_rounded, size: 20, color: p.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${widget.sourceLabel} → ${widget.targetLabel}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: p.ink,
                      ),
                    ),
                  ),
                  IconAction(
                    label: 'Fermer la traduction'.tr(context),
                    icon: Icons.close_rounded,
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: p.line),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: p.muted,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FutureBuilder<String>(
                      future: _result,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator.adaptive(),
                                ),
                                SizedBox(width: 12),
                                Flexible(
                                  child: Text(
                                    'Traduction en cours…'.tr(context),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        if (snapshot.hasError ||
                            (snapshot.data?.trim().isEmpty ?? true)) {
                          final unavailable =
                              snapshot.error is SelectionTranslationUnavailable;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  unavailable
                                      ? (snapshot.error!
                                              as SelectionTranslationUnavailable)
                                          .message
                                      : 'La traduction n’a pas abouti.'.tr(
                                        context,
                                      ),
                                  style: TextStyle(
                                    color: p.muted,
                                    fontSize: 15,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                              if (!unavailable) ...[
                                const SizedBox(height: 12),
                                AdaptiveButton(
                                  label: 'Réessayer'.tr(context),
                                  onPressed:
                                      () => setState(() {
                                        _result = Future.sync(
                                          () => widget.translate(widget.text),
                                        );
                                      }),
                                ),
                              ],
                            ],
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Semantics(
                              liveRegion: true,
                              child: SelectableText(
                                snapshot.data!,
                                style: TextStyle(
                                  fontFamily: LisiereTheme.serif,
                                  fontSize: 19,
                                  height: 1.5,
                                  color: p.ink,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            AdaptiveButton(
                              label: (_copied
                                      ? 'Copié'
                                      : 'Copier la traduction')
                                  .tr(context),
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: snapshot.data!),
                                );
                                if (mounted) setState(() => _copied = true);
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
