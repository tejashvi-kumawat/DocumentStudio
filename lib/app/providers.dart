import 'package:document_studio/core/perf/render_budget.dart';
import 'package:document_studio/core/storage/linux_document_portal.dart';
import 'package:document_studio/core/jobs/job_runner.dart';
import 'package:document_studio/core/settings/settings_repository.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/core/storage/local_file_storage.dart';
import 'package:document_studio/core/storage/favorite_files_repository.dart';
import 'package:document_studio/core/storage/recent_files_repository.dart';
import 'package:document_studio/infrastructure/pdf/pdf_render_port.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/compression/compress_service.dart';
import 'package:document_studio/features/form_sign/pdf_page_stamp_service.dart';
import 'package:document_studio/features/page_management/page_thumbnail_cache.dart';
import 'package:document_studio/features/pdf_markup/pdf_markup_service.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_service.dart';
import 'package:document_studio/infrastructure/organize/blank_page_factory.dart';
import 'package:document_studio/infrastructure/organize/page_organize_service.dart';
import 'package:document_studio/infrastructure/pdf/composite_structure_adapter.dart';
import 'package:document_studio/infrastructure/pdf/pdf_structure_port.dart';
import 'package:document_studio/infrastructure/pdf/pdfrx_render_adapter.dart';
import 'package:document_studio/infrastructure/pdf/qpdf_encrypt_adapter.dart';
import 'package:document_studio/infrastructure/pdf/qpdf_metadata_adapter.dart';
import 'package:document_studio/infrastructure/pdf/routing_pdf_encrypt_adapter.dart';
import 'package:document_studio/infrastructure/pdf/routing_pdf_metadata_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final fileStorageProvider = Provider<FileStoragePort>((ref) {
  return LocalFileStorage();
});

final jobRunnerProvider = Provider<JobRunner>((ref) => JobRunner());

final pdfRenderPortProvider = Provider<PdfRenderPort>((ref) {
  return PdfrxRenderAdapter();
});

final pdfStructurePortProvider = Provider<PdfStructurePort>((ref) {
  return CompositePdfStructureAdapter();
});

final pdfEncryptPortProvider = Provider<PdfEncryptPort>((ref) {
  return RoutingPdfEncryptAdapter();
});

final pdfMetadataPortProvider = Provider<PdfMetadataPort>((ref) {
  return RoutingPdfMetadataAdapter();
});

final compressServiceProvider = Provider<CompressService>((ref) {
  return CompressService(
    structure: ref.watch(pdfStructurePortProvider),
    storage: ref.watch(fileStorageProvider),
    jobs: ref.watch(jobRunnerProvider),
  );
});

final pdfOverlayServiceProvider = Provider<PdfOverlayService>((ref) {
  return PdfOverlayService(render: ref.watch(pdfRenderPortProvider));
});

final pdfMarkupServiceProvider = Provider<PdfMarkupService>((ref) {
  return PdfMarkupService(
    overlay: ref.watch(pdfOverlayServiceProvider),
    storage: ref.watch(fileStorageProvider),
    jobs: ref.watch(jobRunnerProvider),
  );
});

final pageOrganizeServiceProvider = Provider<PageOrganizeService>((ref) {
  return PageOrganizeService(
    structure: ref.watch(pdfStructurePortProvider),
    storage: ref.watch(fileStorageProvider),
    jobs: ref.watch(jobRunnerProvider),
  );
});

final blankPageFactoryProvider = Provider<BlankPageFactory>((ref) {
  return BlankPageFactory(ref.watch(fileStorageProvider));
});

final organizeThumbCacheProvider = Provider<PageThumbnailCache>((ref) {
  return PageThumbnailCache();
});

final pdfPageStampServiceProvider = Provider<PdfPageStampService>((ref) {
  return PdfPageStampService(
    overlay: ref.watch(pdfOverlayServiceProvider),
    storage: ref.watch(fileStorageProvider),
    jobs: ref.watch(jobRunnerProvider),
  );
});

final settingsRepositoryProvider = FutureProvider<SettingsRepository>((
  ref,
) async {
  return SettingsRepository.create();
});

final recentFilesRepositoryProvider = FutureProvider<RecentFilesRepository>((
  ref,
) async {
  return RecentFilesRepository.create();
});

final favoriteFilesRepositoryProvider = FutureProvider<FavoriteFilesRepository>(
  (ref) async {
    return FavoriteFilesRepository.create();
  },
);

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.light;

  Future<void> load() async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    state = repo.themeMode;
  }

  Future<void> setMode(ThemeMode mode) async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    await repo.setThemeMode(mode);
    state = mode;
  }
}

final recentsProvider =
    AsyncNotifierProvider<RecentsNotifier, List<LocalFileRef>>(
      RecentsNotifier.new,
    );

class RecentsNotifier extends AsyncNotifier<List<LocalFileRef>> {
  /// Portal → host path; drops session working copies (`ds_sess_*`).
  Future<LocalFileRef?> _forRecents(LocalFileRef fileRef) async {
    if (RecentFilesRepository.isSessionWorkingCopyPath(fileRef.path)) {
      return null;
    }
    final hostPath = await LinuxDocumentPortal.resolve(fileRef.path);
    if (RecentFilesRepository.isSessionWorkingCopyPath(hostPath)) {
      return null;
    }
    return hostPath == fileRef.path ? fileRef : fileRef.copyWithPath(hostPath);
  }

  Future<List<LocalFileRef>> _normalizeStored(List<LocalFileRef> list) async {
    final mapped = <LocalFileRef>[];
    for (final f in list) {
      final prepared = await _forRecents(f);
      if (prepared != null) mapped.add(prepared);
    }
    return RecentFilesRepository.collapseDuplicates(mapped);
  }

  @override
  Future<List<LocalFileRef>> build() async {
    final repo = await ref.read(recentFilesRepositoryProvider.future);
    final collapsed = await _normalizeStored(repo.load());
    final previous = repo.load();
    final changed =
        previous.length != collapsed.length ||
        !_sameRecentPaths(previous, collapsed);
    if (changed) {
      await repo.replaceAll(collapsed);
    }
    return collapsed;
  }

  static bool _sameRecentPaths(List<LocalFileRef> a, List<LocalFileRef> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].path != b[i].path) return false;
    }
    return true;
  }

  Future<void> refresh() async {
    state = AsyncData(await build());
  }

  Future<void> addRecent(LocalFileRef fileRef) async {
    final prepared = await _forRecents(fileRef);
    if (prepared == null) return;
    final repo = await ref.read(recentFilesRepositoryProvider.future);
    // Re-collapse stored aliases (portal / old host / leftover temps) so the
    // new entry replaces every prior path for the same document.
    final collapsed = await _normalizeStored([prepared, ...repo.load()]);
    await repo.replaceAll(collapsed);
    state = AsyncData(collapsed);
  }

  Future<void> removeRecent(String path) async {
    final repo = await ref.read(recentFilesRepositoryProvider.future);
    final hostPath = await LinuxDocumentPortal.resolve(path);
    await repo.remove(hostPath);
    if (hostPath != path) {
      await repo.remove(path);
    }
    state = AsyncData(await _normalizeStored(repo.load()));
  }

  Future<void> clearRecents() async {
    final repo = await ref.read(recentFilesRepositoryProvider.future);
    await repo.clear();
    state = const AsyncData([]);
  }
}

final favoritesProvider =
    AsyncNotifierProvider<FavoritesNotifier, List<LocalFileRef>>(
      FavoritesNotifier.new,
    );

class FavoritesNotifier extends AsyncNotifier<List<LocalFileRef>> {
  @override
  Future<List<LocalFileRef>> build() async {
    final repo = await ref.read(favoriteFilesRepositoryProvider.future);
    return repo.load();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await build());
  }

  Future<void> toggleFavorite(LocalFileRef fileRef) async {
    final repo = await ref.read(favoriteFilesRepositoryProvider.future);
    await repo.toggle(fileRef);
    await refresh();
  }

  bool isFavorite(String path) {
    final list = state.value;
    if (list == null) return false;
    return list.any((f) => f.path == path);
  }
}

/// Viewer defaults chosen in Settings (applied when a document opens).
class ViewerPrefs {
  const ViewerPrefs({
    this.zoom = 'fitWidth',
    this.display = 'continuous',
    this.quality = 'auto',
    this.textFamily = 'sans',
    this.textSize = 14,
  });

  final String zoom;
  final String display;
  final String quality;
  final String textFamily;
  final double textSize;

  ViewerPrefs copyWith({
    String? zoom,
    String? display,
    String? quality,
    String? textFamily,
    double? textSize,
  }) => ViewerPrefs(
    zoom: zoom ?? this.zoom,
    display: display ?? this.display,
    quality: quality ?? this.quality,
    textFamily: textFamily ?? this.textFamily,
    textSize: textSize ?? this.textSize,
  );
}

final viewerPrefsProvider = NotifierProvider<ViewerPrefsNotifier, ViewerPrefs>(
  ViewerPrefsNotifier.new,
);

class ViewerPrefsNotifier extends Notifier<ViewerPrefs> {
  @override
  ViewerPrefs build() {
    _load();
    return const ViewerPrefs();
  }

  Future<void> _load() async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    RenderBudget.userQuality = repo.renderQuality;
    state = ViewerPrefs(
      zoom: repo.defaultZoom,
      display: repo.defaultPageDisplay,
      quality: repo.renderQuality,
      textFamily: repo.newTextFamily,
      textSize: repo.newTextSize,
    );
  }

  Future<void> setQuality(String v) async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    await repo.setRenderQuality(v);
    RenderBudget.userQuality = v;
    state = state.copyWith(quality: v);
  }

  Future<void> setTextFamily(String v) async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    await repo.setNewTextFamily(v);
    state = state.copyWith(textFamily: v);
  }

  Future<void> setTextSize(double v) async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    await repo.setNewTextSize(v);
    state = state.copyWith(textSize: v);
  }

  Future<void> setZoom(String v) async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    await repo.setDefaultZoom(v);
    state = state.copyWith(zoom: v);
  }

  Future<void> setDisplay(String v) async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    await repo.setDefaultPageDisplay(v);
    state = state.copyWith(display: v);
  }
}
