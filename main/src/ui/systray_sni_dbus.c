/*
 * Manual D-Bus registration for StatusNotifierItem with IconPixmap.
 *
 * Vala's [DBus] annotation can't handle the a(iiay) type for IconPixmap
 * (it can't create a GObject property for struct arrays), so we register
 * the interface manually with proper XML introspection.
 */

#include "systray_sni_dbus.h"

static const gchar sni_xml[] =
"<node>"
"  <interface name='org.kde.StatusNotifierItem'>"
"    <property name='Status'        type='s'       access='read'/>"
"    <property name='IconName'      type='s'       access='read'/>"
"    <property name='IconThemePath' type='s'       access='read'/>"
"    <property name='IconPixmap'    type='a(iiay)' access='read'/>"
"    <property name='Title'         type='s'       access='read'/>"
"    <property name='Category'      type='s'       access='read'/>"
"    <property name='Id'            type='s'       access='read'/>"
"    <property name='ItemIsMenu'    type='b'       access='read'/>"
"    <property name='Menu'          type='o'       access='read'/>"
"    <method name='Activate'>"
"      <arg name='x' type='i' direction='in'/>"
"      <arg name='y' type='i' direction='in'/>"
"    </method>"
"    <method name='SecondaryActivate'>"
"      <arg name='x' type='i' direction='in'/>"
"      <arg name='y' type='i' direction='in'/>"
"    </method>"
"    <method name='ContextMenu'>"
"      <arg name='x' type='i' direction='in'/>"
"      <arg name='y' type='i' direction='in'/>"
"    </method>"
"    <method name='Scroll'>"
"      <arg name='delta' type='i' direction='in'/>"
"      <arg name='orientation' type='s' direction='in'/>"
"    </method>"
"    <signal name='NewIcon'/>"
"    <signal name='NewStatus'>"
"      <arg name='status' type='s'/>"
"    </signal>"
"  </interface>"
"</node>";

typedef struct {
    SniGetPropertyFunc get_property;
    SniMethodCallFunc  method_call;
    gpointer           user_data;
} SniCallbacks;

static GDBusNodeInfo *node_info = NULL;

static GVariant *
handle_get_property (GDBusConnection  *connection,
                     const gchar      *sender,
                     const gchar      *object_path,
                     const gchar      *interface_name,
                     const gchar      *property_name,
                     GError          **error,
                     gpointer          data)
{
    SniCallbacks *cb = data;
    return cb->get_property (property_name, cb->user_data);
}

static void
handle_method_call (GDBusConnection       *connection,
                    const gchar           *sender,
                    const gchar           *object_path,
                    const gchar           *interface_name,
                    const gchar           *method_name,
                    GVariant              *parameters,
                    GDBusMethodInvocation *invocation,
                    gpointer               data)
{
    SniCallbacks *cb = data;
    cb->method_call (method_name, parameters, invocation, cb->user_data);
}

static const GDBusInterfaceVTable sni_vtable = {
    handle_method_call,
    handle_get_property,
    NULL
};

static void
destroy_callbacks (gpointer data)
{
    g_free (data);
}

guint
sni_dbus_register (GDBusConnection     *connection,
                   const gchar          *object_path,
                   SniGetPropertyFunc    get_property_func,
                   SniMethodCallFunc     method_call_func,
                   gpointer              user_data,
                   GError              **error)
{
    if (node_info == NULL)
        node_info = g_dbus_node_info_new_for_xml (sni_xml, NULL);

    SniCallbacks *cb = g_new0 (SniCallbacks, 1);
    cb->get_property = get_property_func;
    cb->method_call  = method_call_func;
    cb->user_data    = user_data;

    return g_dbus_connection_register_object (connection, object_path,
        node_info->interfaces[0], &sni_vtable, cb, destroy_callbacks, error);
}

void
sni_dbus_emit_signal (GDBusConnection *connection,
                      const gchar     *object_path,
                      const gchar     *signal_name,
                      GVariant        *parameters)
{
    g_dbus_connection_emit_signal (connection, NULL, object_path,
        "org.kde.StatusNotifierItem", signal_name, parameters, NULL);
}
