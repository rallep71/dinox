plugin_name = 'tor-manager'
plugin_sources = files(
    'src/plugin.vala',
    'src/register_plugin.vala',
    'src/tor_manager.vala',
    'src/tor_controller.vala',
    'src/moat_client.vala',
    'src/settings_page.vala',
    'src/ui_indicator.vala'
)

shared_module(plugin_name,
    plugin_sources,
    c_args: [
        '-DG_LOG_DOMAIN="tor-manager"',
        '-DGETTEXT_PACKAGE="dino"',
        '-DLOCALE_INSTALL_DIR="@0@"'.format(get_option('prefix') / get_option('localedir')),
    ],
    dependencies: [
        dep_dino,
        dep_glib,
        dep_gio,
        dependency('gtk4'),
        dependency('libadwaita-1'),
        dependency('libsoup-3.0'),
        dep_gee,
        dep_xmpp_vala,
        dep_qlite
    ],
    install: true,
    install_dir: get_option('libdir') / get_option('plugindir')
)
