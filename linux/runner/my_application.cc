#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

#include <gdk-pixbuf/gdk-pixbuf.h>

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* open_channel;
  GtkWindow* window;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Icon theme / desktop Icon= name used for dock matching.
static const gchar* kDesktopIconName = "com.documentstudio.document_studio";

// Resolve Document Studio icon next to the binary or from bundled assets.
// Prefer the padded square app_icon for the dock; fall back to brand assets.
static gchar* document_studio_icon_path() {
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  if (exe == nullptr) {
    return nullptr;
  }
  g_autofree gchar* exe_dir = g_path_get_dirname(exe);
  g_autofree gchar* c0 =
      g_build_filename(exe_dir, "icons", "app_icon.png", nullptr);
  g_autofree gchar* c1 = g_build_filename(exe_dir, "app_icon.png", nullptr);
  g_autofree gchar* c2 = g_build_filename(
      exe_dir, "data", "flutter_assets", "assets", "brand",
      "document_studio_logo_transparent.png", nullptr);
  g_autofree gchar* c3 = g_build_filename(
      exe_dir, "data", "flutter_assets", "assets", "brand",
      "document_studio_logo.png", nullptr);
  const gchar* paths[] = {c0, c1, c2, c3, nullptr};
  for (int i = 0; paths[i] != nullptr; i++) {
    if (g_file_test(paths[i], G_FILE_TEST_IS_REGULAR)) {
      return g_strdup(paths[i]);
    }
  }
  return nullptr;
}

// Load the brand PNG and register it as the GTK default icon *before* any
// window is realized so GNOME/Wayland pick it up for the dock.
static void apply_default_icon() {
  g_autofree gchar* icon_path = document_studio_icon_path();
  if (icon_path == nullptr) {
    // Theme name may still resolve if a user/system hicolor icon is installed.
    gtk_window_set_default_icon_name(kDesktopIconName);
    return;
  }
  g_autoptr(GError) error = nullptr;
  GdkPixbuf* pixbuf = gdk_pixbuf_new_from_file(icon_path, &error);
  if (pixbuf == nullptr) {
    g_warning("Document Studio icon load failed (%s): %s", icon_path,
              error != nullptr ? error->message : "unknown");
    gtk_window_set_default_icon_name(kDesktopIconName);
    return;
  }
  gtk_window_set_default_icon(pixbuf);
  g_object_unref(pixbuf);
  // Also advertise the theme name so .desktop Icon= matches.
  gtk_window_set_default_icon_name(kDesktopIconName);
}

static void apply_window_icon(GtkWindow* window) {
  g_autofree gchar* icon_path = document_studio_icon_path();
  if (icon_path != nullptr) {
    g_autoptr(GError) error = nullptr;
    GdkPixbuf* pixbuf = gdk_pixbuf_new_from_file(icon_path, &error);
    if (pixbuf != nullptr) {
      gtk_window_set_icon(window, pixbuf);
      g_object_unref(pixbuf);
    } else {
      g_warning("Document Studio window icon load failed (%s): %s", icon_path,
                error != nullptr ? error->message : "unknown");
    }
  }
  gtk_window_set_icon_name(window, kDesktopIconName);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;

  gtk_window_set_title(window, "Document Studio");

  // Flutter draws the title bar (document tabs + window controls). Setting an
  // invisible custom titlebar keeps GTK client-side decorations — compositor
  // shadow, resize edges, and snapping — without the native header bar.
  // DOCUMENT_STUDIO_NATIVE_TITLEBAR=1 restores the classic system title bar.
  const gboolean custom_frame =
      g_strcmp0(g_getenv("DOCUMENT_STUDIO_NATIVE_TITLEBAR"), "1") != 0;
  gboolean transparent = FALSE;
  if (custom_frame) {
    GtkWidget* hidden_titlebar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_window_set_titlebar(window, hidden_titlebar);
    g_setenv("DOCUMENT_STUDIO_CUSTOM_FRAME", "1", TRUE);

    // With a compositor, use an RGBA visual so Flutter can round the corners
    // and GTK's shadow follows the same radius.
    GdkScreen* screen = gtk_window_get_screen(window);
    GdkVisual* rgba_visual = gdk_screen_get_rgba_visual(screen);
    if (rgba_visual != nullptr && gdk_screen_is_composited(screen)) {
      gtk_widget_set_visual(GTK_WIDGET(window), rgba_visual);
      gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
      GtkStyleContext* style = gtk_widget_get_style_context(GTK_WIDGET(window));
      gtk_style_context_add_class(style, "document-studio-window");
      g_autoptr(GtkCssProvider) css = gtk_css_provider_new();
      gtk_css_provider_load_from_data(
          css,
          "window.document-studio-window { background-color: transparent; }"
          "window.document-studio-window decoration { border-radius: 10px; }"
          "window.document-studio-window.maximized decoration,"
          "window.document-studio-window.fullscreen decoration,"
          "window.document-studio-window.tiled decoration {"
          " border-radius: 0; }",
          -1, nullptr);
      gtk_style_context_add_provider_for_screen(
          screen, GTK_STYLE_PROVIDER(css),
          GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
      transparent = TRUE;
      g_setenv("DOCUMENT_STUDIO_TRANSPARENT", "1", TRUE);
    }
  }

  // Fallback only, used before the window is mapped. Once the compositor
  // has sized the window, startup must not unmaximize back to this size:
  // the embedder would wait for a 1280x720 frame while the live window
  // is already a different size. Minimum matches DsWindow.minimumSize.
  gtk_window_set_default_size(window, 1280, 720);
  GdkGeometry geometry = {};
  geometry.min_width = 560;
  geometry.min_height = 420;
  gtk_window_set_geometry_hints(window, nullptr, &geometry, GDK_HINT_MIN_SIZE);
  // Icon must be set before realize/show for reliable dock branding.
  apply_window_icon(window);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, transparent ? "#00000000" : "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // Files forwarded by a second launch arrive on this channel (see
  // open_files_cb), so they open as tabs in this window.
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->open_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "document_studio/open", FL_METHOD_CODEC(codec));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Runs in the first (primary) instance when another launch forwards its
// arguments: opens them in a new tab and brings the window forward.
static void open_files_cb(GSimpleAction* action, GVariant* parameter,
                          gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->window == nullptr) return;
  if (self->open_channel != nullptr && parameter != nullptr) {
    g_autoptr(FlValue) list = fl_value_new_list();
    gsize n = 0;
    const gchar** items = g_variant_get_strv(parameter, &n);
    for (gsize i = 0; i < n; i++) {
      fl_value_append_take(list, fl_value_new_string(items[i]));
    }
    g_free(items);
    fl_method_channel_invoke_method(self->open_channel, "open", list, nullptr,
                                    nullptr, nullptr);
  }
  gtk_window_present(self->window);
}

// Relative paths mean nothing to the first instance (different working
// directory), so forward absolute ones.
static gchar** absolute_arguments(gchar** args) {
  g_autoptr(GPtrArray) out = g_ptr_array_new();
  for (gchar** it = args; it != nullptr && *it != nullptr; it++) {
    const gchar* a = *it;
    if (a[0] != '-' && !g_path_is_absolute(a) && !g_str_has_prefix(a, "file:")) {
      g_autofree gchar* abs = g_canonicalize_filename(a, nullptr);
      if (g_file_test(abs, G_FILE_TEST_EXISTS)) {
        g_ptr_array_add(out, g_strdup(abs));
        continue;
      }
    }
    g_ptr_array_add(out, g_strdup(a));
  }
  g_ptr_array_add(out, nullptr);
  return reinterpret_cast<gchar**>(g_ptr_array_free(g_steal_pointer(&out), FALSE));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as the binary name.
  self->dart_entrypoint_arguments = absolute_arguments(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  if (g_application_get_is_remote(application)) {
    // Document Studio is already running: hand the files over and exit.
    g_action_group_activate_action(
        G_ACTION_GROUP(application), "open-files",
        g_variant_new_strv(self->dart_entrypoint_arguments, -1));
    *exit_status = 0;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // Set the default icon before any window is created/realized.
  apply_default_icon();
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);

  g_autoptr(GSimpleAction) open_files =
      g_simple_action_new("open-files", G_VARIANT_TYPE_STRING_ARRAY);
  g_signal_connect(open_files, "activate", G_CALLBACK(open_files_cb),
                   application);
  g_action_map_add_action(G_ACTION_MAP(application), G_ACTION(open_files));
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->open_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_DEFAULT_FLAGS, nullptr));
}
