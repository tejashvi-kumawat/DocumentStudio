import 'package:document_studio/design_system/brand/ds_brand_assets.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:flutter/material.dart';

/// Brand lockup from bundled assets (transparent PNG by default).
class DsDocumentStudioLogo extends StatelessWidget {
  const DsDocumentStudioLogo({
    super.key,
    this.height = 48,
    this.compact = false,
    this.useOpaqueAsset = false,
  });

  final double height;
  final bool compact;
  final bool useOpaqueAsset;

  @override
  Widget build(BuildContext context) {
    final asset = useOpaqueAsset
        ? DsBrandAssets.documentStudioLogo
        : DsBrandAssets.documentStudioLogoTransparent;

    return Image.asset(
      asset,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stackTrace) {
        // Missing AssetManifest during hot-restart must not storm exceptions.
        return SizedBox(
          height: height,
          child: const Center(
            child: Icon(Icons.description_outlined, size: 28),
          ),
        );
      },
    );
  }
}

/// Sidebar header: logo mark with optional wordmark spacing.
class DsDocumentStudioRailBrand extends StatelessWidget {
  const DsDocumentStudioRailBrand({super.key, this.extended = true});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    if (!extended) {
      return const DsDocumentStudioLogo(height: 36, compact: true);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DsSpacing.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const DsDocumentStudioLogo(height: 56),
            // Raster lockup includes the wordmark; keep a Text node for tests/a11y.
            Opacity(
              opacity: 0,
              child: Text(
                'Document Studio',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
