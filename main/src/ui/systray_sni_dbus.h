/*
 * Manual D-Bus registration for SNI with IconPixmap a(iiay) support.
 * Vala's [DBus] annotation cannot export complex types like a(iiay)
 * as GObject properties, so we register the interface manually.
 */

#ifndef SYSTRAY_SNI_DBUS_H
#define SYSTRAY_SNI_DBUS_H

#include <gio/gio.h>

typedef GVariant* (*SniGetPropertyFunc) (const gchar *property_name,
                                         gpointer     user_data);

typedef void (*SniMethodCallFunc) (const gchar            *method_name,
                                   GVariant               *parameters,
                                   GDBusMethodInvocation  *invocation,
                                   gpointer                user_data);

guint sni_dbus_register   (GDBusConnection     *connection,
                            const gchar          *object_path,
                            SniGetPropertyFunc    get_property_func,
                            SniMethodCallFunc     method_call_func,
                            gpointer              user_data,
                            GError              **error);

void  sni_dbus_emit_signal (GDBusConnection *connection,
                             const gchar     *object_path,
                             const gchar     *signal_name,
                             GVariant        *parameters);

#endif
