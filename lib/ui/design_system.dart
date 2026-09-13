import 'dart:io';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../domain/book.dart';

abstract final class Space {
  static const double xs = 4,
      sm = 8,
      md = 12,
      lg = 16,
      xl = 24,
      xxl = 32,
      xxxl = 48;
}

/// Semantic colors, shared by Material, Cupertino and our editorial surfaces.
class PaperColors {
  const PaperColors(this.dark);
  final bool dark;
  static PaperColors of(BuildContext context) =>
      PaperColors(Theme.of(context).brightness == Brightness.dark);
  Color get paper => dark ? const Color(0xFF151E19) : const Color(0xFFF7F5EF);
  Color get surface => dark ? const Color(0xFF202D25) : const Color(0xFFFFFEFA);
  Color get inset => dark ? const Color(0xFF29392E) : const Color(0xFFEDEFE8);
  Color get ink => dark ? const Color(0xFFEEEFE7) : const Color(0xFF203B30);
  Color get muted => dark ? const Color(0xFFADB2AE) : const Color(0xFF5D6C61);
  Color get line => dark ? const Color(0xFF3A403C) : const Color(0xFFDCE1D7);
  Color get accent => dark ? const Color(0xFFB3D7B8) : const Color(0xFF28553F);
  Color get onAccent =>
      dark ? const Color(0xFF162E20) : const Color(0xFFF8FAF3);
  Color get highlight =>
      dark ? const Color(0xFFB5DDA5) : const Color(0xFFD5EABF);
  Color get highlightInk => const Color(0xFF173620);
  Color get readingHighlight =>
      dark ? const Color(0xFFF4F1E8) : const Color(0xFF28553F);
  Color get onReadingHighlight =>
      dark ? const Color(0xFF17271F) : const Color(0xFFFFFFFF);
  Color get selection =>
      dark ? const Color(0x997A5A32) : const Color(0x663E7659);
  Color get selectionHandle =>
      dark ? const Color(0xFFF2C879) : const Color(0xFF28553F);
  Color get warning => dark ? const Color(0xFFF0BE9F) : const Color(0xFF8B432D);
  Color get warningSurface =>
      dark ? const Color(0xFF3F2B22) : const Color(0xFFF8EADF);
}

abstract final class LisiereTheme {
  static const serif = 'Georgia';
  static const serifFallback = ['Iowan Old Style', 'Noto Serif', 'serif'];
  static TextStyle editorial(BuildContext context, {double size = 34}) =>
      TextStyle(
        fontFamily: serif,
        fontFamilyFallback: serifFallback,
        fontSize: size,
        height: 1.12,
        fontWeight: FontWeight.w400,
        letterSpacing: -.8,
        color: PaperColors.of(context).ink,
      );
  static ThemeData material(bool dark) {
    final p = PaperColors(dark);
    final base = ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
    );
    return base.copyWith(
      scaffoldBackgroundColor: p.paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: p.accent,
        brightness: base.brightness,
        primary: p.accent,
        onPrimary: p.onAccent,
        surface: p.surface,
        onSurface: p.ink,
      ),
      textTheme: base.textTheme.apply(bodyColor: p.ink, displayColor: p.ink),
      dividerColor: p.line,
      appBarTheme: AppBarTheme(
        backgroundColor: p.paper,
        foregroundColor: p.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.inset,
      ),
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: p.selection,
        selectionHandleColor: p.selectionHandle,
        cursorColor: p.selectionHandle,
      ),
      iconTheme: IconThemeData(color: p.ink),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.paper,
        indicatorColor: p.inset,
        elevation: 0,
      ),
    );
  }

  static CupertinoThemeData cupertino(bool dark) {
    final p = PaperColors(dark);
    return CupertinoThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      primaryColor: p.accent,
      primaryContrastingColor: p.onAccent,
      scaffoldBackgroundColor: p.paper,
      barBackgroundColor: p.paper,
      textTheme: CupertinoTextThemeData(
        primaryColor: p.accent,
        textStyle: TextStyle(fontSize: 17, color: p.ink),
      ),
    );
  }
}

class SurfacePanel extends StatelessWidget {
  const SurfacePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  @override
  Widget build(BuildContext context) => AdaptiveCard(
    padding: padding,
    color: color ?? PaperColors.of(context).surface,
    borderRadius: BorderRadius.circular(24),
    elevation: 0,
    child: child,
  );
}

class PageIntro extends StatelessWidget {
  const PageIntro({
    super.key,
    required this.kicker,
    required this.title,
    this.subtitle,
  });
  final String kicker, title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) {
    final p = PaperColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kicker.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 2.2,
            color: p.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        Text(title, style: LisiereTheme.editorial(context, size: 36)),
        if (subtitle != null) ...[
          const SizedBox(height: 14),
          Text(
            subtitle!,
            style: TextStyle(fontSize: 15, height: 1.5, color: p.muted),
          ),
        ],
      ],
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
          ),
        ),
        // ignore: use_null_aware_elements
        if (trailing != null) trailing!,
      ],
    ),
  );
}

class PrimaryAction extends StatelessWidget {
  const PrimaryAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.subtitle,
  });
  final String label;
  final String? subtitle;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final p = PaperColors.of(context);
    final detail = subtitle;
    return SizedBox(
      width: double.infinity,
      child:
          detail == null
              ? AdaptiveButton(
                onPressed: onPressed,
                label: label,
                enabled: onPressed != null,
                color: p.accent,
                textColor: p.onAccent,
                minSize: const Size(48, 52),
                borderRadius: BorderRadius.circular(16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
              )
              : Semantics(
                button: true,
                enabled: onPressed != null,
                label: '$label, $detail',
                child: AdaptiveButton.child(
                  useNative: false,
                  onPressed: onPressed,
                  enabled: onPressed != null,
                  color: p.accent,
                  minSize: const Size(48, 64),
                  borderRadius: BorderRadius.circular(16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: p.onAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        style: TextStyle(
                          color: p.onAccent.withValues(alpha: .72),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
    );
  }
}

class IconAction extends StatelessWidget {
  const IconAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.prominent = false,
    this.large = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool prominent, large;
  @override
  Widget build(BuildContext context) {
    final p = PaperColors.of(context);
    return Semantics(
      label: label,
      button: true,
      enabled: onPressed != null,
      child: AdaptiveTooltip(
        message: label,
        child: AdaptiveButton.icon(
          onPressed: onPressed,
          enabled: onPressed != null,
          icon: icon,
          color: prominent ? p.accent : p.inset,
          iconColor: prominent ? p.onAccent : p.ink,
          minSize: Size.square(large ? 64 : 48),
          borderRadius: BorderRadius.circular(large ? 32 : 24),
          useSmoothRectangleBorder: false,
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(
    this.label, {
    super.key,
    this.icon = Icons.check_circle_outline,
  });
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final p = PaperColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: p.inset,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: p.muted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: p.muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Notice extends StatelessWidget {
  const Notice(this.message, {super.key, this.onClose});
  final String message;
  final VoidCallback? onClose;
  @override
  Widget build(BuildContext context) {
    final p = PaperColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: p.warningSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: p.warning, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, height: 1.45, color: p.warning),
            ),
          ),
          if (onClose != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: IconAction(
                label: 'Fermer le message',
                icon: Icons.close,
                onPressed: onClose,
              ),
            ),
        ],
      ),
    );
  }
}

class SettingSwitch extends StatelessWidget {
  const SettingSwitch({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: PaperColors.of(context).muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        IgnorePointer(
          ignoring: onChanged == null,
          child: AdaptiveSwitch(
            value: value,
            onChanged: (v) => onChanged?.call(v),
          ),
        ),
      ],
    ),
  );
}

class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onPressed,
    this.leading,
    this.trailing,
  });
  final String title, subtitle;
  final bool selected;
  final VoidCallback? onPressed;
  final Widget? leading;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final p = PaperColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        selected: selected,
        child: AdaptiveButton.child(
          useNative: false,
          onPressed: onPressed,
          enabled: onPressed != null,
          color: selected ? p.inset : p.surface,
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(18),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: p.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: p.muted,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 21,
                color: selected ? p.accent : p.muted,
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Pure Flutter fallback cover; no remote images, fonts, or invented book art.
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.book,
    this.width = 88,
    this.height = 124,
  });
  final ReadingBook book;
  final double width, height;
  @override
  Widget build(BuildContext context) {
    final cover = book.coverPath;
    final fallback = Container(
      decoration: const BoxDecoration(color: Color(0xFF365744)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: -width * .45,
            bottom: -height * .13,
            child: Container(
              width: width * 1.2,
              height: height * .75,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF95AD83), width: 1),
              ),
            ),
          ),
          Positioned(
            right: -width * .2,
            bottom: -height * .25,
            child: Container(
              width: width,
              height: height * .85,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF95AD83), width: 1),
              ),
            ),
          ),
          Positioned(
            left: 4,
            top: 0,
            bottom: 0,
            child: Container(width: 1, color: const Color(0xFF64816A)),
          ),
          Padding(
            padding: EdgeInsets.all(width * .14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'L',
                  style: TextStyle(
                    fontFamily: LisiereTheme.serif,
                    color: const Color(0xFFE6EACD),
                    fontSize: width * .22,
                  ),
                ),
                const Spacer(),
                if (width > 70)
                  Text(
                    book.title,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFFF6F1DB),
                      fontSize: width * .13,
                      height: 1.13,
                      fontFamily: LisiereTheme.serif,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(width > 70 ? 8 : 5),
          child:
              cover == null
                  ? fallback
                  : Image.file(
                    File(cover),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => fallback,
                  ),
        ),
      ),
    );
  }
}

Future<T?> openPage<T>(BuildContext context, Widget child) =>
    Navigator.of(context).push<T>(
      Platform.isIOS
          ? CupertinoPageRoute<T>(builder: (_) => child)
          : MaterialPageRoute<T>(builder: (_) => child),
    );
