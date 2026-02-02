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
    dependencies: [
        dep_dino,
        dep_glib,
        dep_gio,
        dependency('gtk4'),
        dependency('libadwaita-1'),
        dependency('json-glib-1.0'),
        dependency('libsoup-3.0'),
        dep_gee,
        dep_xmpp_vala,
        dep_qlite
    ],
    install: true,
    install_dir: get_option('libdir') / 'dino' / 'plugins'
)
