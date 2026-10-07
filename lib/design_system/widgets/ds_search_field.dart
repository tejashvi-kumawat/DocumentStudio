import 'package:document_studio/design_system/ds_colors.dart';
import 'package:flutter/material.dart';

/// Dense outline search field shared by Home, Organize hub, and tool catalogs.
class DsSearchField extends StatelessWidget {
  const DsSearchField({
    super.key,
    this.fieldKey,
    required this.hintText,
    this.onChanged,
    this.autofocus = false,
  });

  final Key? fieldKey;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;

    return TextField(
      key: fieldKey,
      autofocus: autofocus,
      decoration: InputDecoration(
        hintText: hintText,
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 20),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
      ),
      onChanged: onChanged,
    );
  }
}
