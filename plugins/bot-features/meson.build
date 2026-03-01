dependencies = [
    dep_dino,
    dep_gee,
    dep_gio,
    dep_glib,
    dep_gmodule,
    dep_crypto_vala,
    dependency('json-glib-1.0'),
    dep_libsoup,
    dep_qlite,
    dep_xmpp_vala,
    dep_libomemo_c,
    dep_libgcrypt,
    dep_gtk4,
    dep_libadwaita,
    dependency('gnutls'),
]

# Strip UI classes (Gtk/Adw) and register_plugin from omemo internal vapi
omemo_vapi_stripped = custom_target('omemo-vapi-stripped',
    input: vapi_omemo_internal,
    output: 'omemo-bot.vapi',
    command: [find_program('python3'),
        meson.project_source_root() / 'plugins/bot-features/strip_omemo_vapi.py',
        '@INPUT@'],
    capture: true,
)
dep_omemo_bot = declare_dependency(
    link_args: [lib_omemo.full_path(), '-Wl,-rpath,' + meson.project_build_root() / 'plugins/omemo'],
    include_directories: [
        include_directories('../omemo'),
        include_directories('../omemo/src'),
    ],
    sources: [omemo_vapi_stripped],
)

sources = files(
    'src/plugin.vala',
    'src/register_plugin.vala',
    'src/bot_utils.vala',
    'src/bot_registry.vala',
    'src/token_manager.vala',
    'src/auth_middleware.vala',
    'src/rate_limiter.vala',
    'src/http_server.vala',
    'src/session_pool.vala',
    'src/message_router.vala',
    'src/webhook_dispatcher.vala',
    'src/botfather_handler.vala',
    'src/ejabberd_api.vala',
    'src/bot_omemo.vala',
    'src/ai_integration.vala',
    'src/telegram_bridge.vala',
)
c_sources = files(
    'src/cert_gen.c',
)
vapi_sources = files(
    'vapi/cert_gen.vapi',
)
c_args = [
    '-DG_LOG_DOMAIN="bot-features"',
    '-DGETTEXT_PACKAGE="dino"',
]
vala_args = [
    '--vapidir', meson.project_source_root() / 'plugins/omemo/vapi',
    '--vapidir', meson.project_source_root() / 'plugins/bot-features/vapi',
]
lib_bot_features = shared_library('bot-features', sources + c_sources + vapi_sources, name_prefix: '', c_args: c_args, vala_args: vala_args, include_directories: include_directories('src'), dependencies: dependencies + dep_omemo_bot, install: true, install_dir: get_option('libdir') / get_option('plugindir'), install_rpath: default_install_rpath)
dep_bot_features = declare_dependency(link_with: lib_bot_features, include_directories: include_directories('.'))
summary('BotFather API and Bot Management (bot-features)', dep_bot_features, section: 'Plugins')

# Unit tests for bot-features (standalone, only rate_limiter.vala needs Gee)
bot_test_sources = files(
    'tests/common.vala',
    'tests/testcase.vala',
    'tests/bot_tests.vala',
    'tests/audit_tests.vala',
    'src/rate_limiter.vala',
)
exe_bot_test = executable('bot-features-test', bot_test_sources, c_args: ['-DG_LOG_DOMAIN="bot-features-test"'], dependencies: [dep_gee, dep_glib, dep_gio], install: false)
test('bot-features-test', exe_bot_test)
