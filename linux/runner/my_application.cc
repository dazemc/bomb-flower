#include <bitsdojo_window_linux/bitsdojo_window_plugin.h>

#include "my_application.h"

#include <flutter_linux/flutter_linux.h>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Method channel that hands paths dropped onto the window to Dart. The Dart
// side registers the handler for the same name; keep both in sync.
static constexpr char kDropChannelName[] = "bomb_flower/drop";
// Key under which the channel is attached to the FlView so the drop callback
// can reach it. The channel is created once per view and destroyed with it.
static constexpr char kDropChannelKey[] = "bomb-flower-drop-channel";

// Called when URIs are dropped on the Flutter view. Only text/uri-list drops
// reach this handler; the first URI is forwarded to Dart when it resolves to a
// local file. Directories are not filtered here, Dart validates them.
static void view_drag_data_received_cb(GtkWidget* widget,
                                       GdkDragContext* context, gint x, gint y,
                                       GtkSelectionData* data, guint info,
                                       guint time, gpointer user_data) {
  (void)x;
  (void)y;
  (void)info;
  (void)user_data;

  gboolean handled = FALSE;
  gchar** uris = gtk_selection_data_get_uris(data);
  if (uris != nullptr && uris[0] != nullptr) {
    g_autofree gchar* path = g_filename_from_uri(uris[0], nullptr, nullptr);
    // Non-local URIs (http, ...) resolve to nothing; ignore them silently.
    if (path != nullptr && path[0] != '\0') {
      FlMethodChannel* channel = FL_METHOD_CHANNEL(
          g_object_get_data(G_OBJECT(widget), kDropChannelKey));
      if (channel != nullptr) {
        fl_method_channel_invoke_method(channel, "folderDropped",
                                        fl_value_new_string(path), nullptr,
                                        nullptr, nullptr);
        handled = TRUE;
      }
    }
  }
  g_strfreev(uris);

  gtk_drag_finish(context, handled, FALSE, time);
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
  // bitsdojo_window: remove the native frame; the Dart side draws its own
  // title bar. Window size is set from Dart (appWindow.size / minSize).
  auto bdw = bitsdojo_window_from(window);
  bdw->setCustomFrame(true);
  // gtk_window_set_default_size(window, 1280, 720);

  // If you want to use a header bar, uncomment the following lines.
  // Header bars are commonly used in GNOME based desktop environments and
  // allow additional widgets to be added to the title bar.
  // See https://docs.gtk.org/gtk3/class.HeaderBar.html
  // GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
  // gtk_widget_show(GTK_WIDGET(header_bar));
  // gtk_header_bar_set_show_close_button(header_bar, TRUE);
  // gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));

  gtk_window_set_title(window, "Bomb Flower");

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // Accept folders dragged from the file manager. GTK_DEST_DEFAULT_ALL has no
  // default action, so view_drag_data_received_cb finishes the drag itself.
  gtk_drag_dest_set(GTK_WIDGET(view), GTK_DEST_DEFAULT_ALL, nullptr, 0,
                    GDK_ACTION_COPY);
  gtk_drag_dest_add_uri_targets(GTK_WIDGET(view));
  g_signal_connect(view, "drag-data-received",
                   G_CALLBACK(view_drag_data_received_cb), nullptr);

  // One channel for the lifetime of the view; g_object_set_data_full frees it
  // when the view is destroyed.
  FlMethodChannel* drop_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), kDropChannelName,
      FL_METHOD_CODEC(fl_standard_method_codec_new()));
  g_object_set_data_full(G_OBJECT(view), kDropChannelKey, drop_channel,
                         (GDestroyNotify)g_object_unref);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
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
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
