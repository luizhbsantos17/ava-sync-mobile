#include <gtk/gtk.h>

#include "my_application.h"

int main(int argc, char** argv) {
  // O navegador do Q-Acadêmico (WebKitGTK) fica por cima da tela do Flutter num
  // GtkOverlay. No Wayland nativo ele não aparece (a superfície do Flutter cobre),
  // então preferimos X11 (XWayland) e só usamos Wayland se não houver X11.
  // Quem quiser outro, ainda pode escolher com GDK_BACKEND.
  if (g_getenv("GDK_BACKEND") == nullptr) gdk_set_allowed_backends("x11,wayland");

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
