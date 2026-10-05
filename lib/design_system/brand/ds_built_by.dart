import 'package:document_studio/app/app_version.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// "Built by Tejashvi Kumawat with ♥" — small credit line. Tapping opens the
/// author's GitHub (unless [link] is false).
class DsBuiltBy extends StatelessWidget {
  const DsBuiltBy({
    super.key,
    this.fontSize = 12,
    this.link = true,
    this.color,
    this.center = true,
  });

  final double fontSize;
  final bool link;
  final Color? color;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final base = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    final text = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Built by ',
          style: TextStyle(fontSize: fontSize, color: base),
        ),
        Text(
          kAuthorName,
          style: TextStyle(
            fontSize: fontSize,
            color: base,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          ' with ',
          style: TextStyle(fontSize: fontSize, color: base),
        ),
        Icon(Icons.favorite, size: fontSize + 1, color: const Color(0xFFE4002B)),
      ],
    );
    if (!link) return text;
    return Tooltip(
      message: kAuthorGithubUrl,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => launchUrl(
            Uri.parse(kAuthorGithubUrl),
            mode: LaunchMode.externalApplication,
          ),
          child: text,
        ),
      ),
    );
  }
}
