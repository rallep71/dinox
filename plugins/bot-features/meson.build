dependencies = [
    dep_dino,
    dep_gee,
    dep_gio,
    dep_glib,
    dep_gmodule,
    dependency('json-glib-1.0'),
    dep_libsoup,
    dep_qlite,
    dep_xmpp_vala,
]
sources = files(
    'src/plugin.vala',
    'src/register_plugin.vala',
    'src/bot_registry.vala',
    'src/token_manager.vala',
    'src/auth_middleware.vala',
    'src/rate_limiter.vala',
    'src/http_server.vala',
    'src/session_pool.vala',
    'src/message_router.vala',
    'src/webhook_dispatcher.vala',
    'src/botfather_handler.vala',
)
lib_bot_features = shared_library('bot-features', sources, name_prefix: '', dependencies: dependencies, install: true, install_dir: get_option('libdir') / get_option('plugindir'), install_rpath: default_install_rpath)
dep_bot_features = declare_dependency(link_with: lib_bot_features, include_directories: include_directories('.'))
summary('BotFather API and Bot Management (bot-features)', dep_bot_features, section: 'Plugins')
