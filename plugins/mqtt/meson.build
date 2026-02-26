# MQTT Plugin for DinoX
#
# Optional plugin — requires libmosquitto-dev
# If libmosquitto is not available, the plugin is skipped.

dep_mosquitto_check = dependency('libmosquitto', required: false)

if dep_mosquitto_check.found()

    # libmosquitto has no system Vala VAPI.
    # We provide our own vapi/mosquitto.vapi and link against -lmosquitto directly.
    # This avoids meson passing --pkg libmosquitto to valac (which would fail).
    cc = meson.get_compiler('c')
    lib_mosquitto_link = cc.find_library('mosquitto')

    dependencies = [
        dep_dino,
        dep_gee,
        dep_gio,
        dep_glib,
        dep_gmodule,
        dep_qlite,
        dep_xmpp_vala,
    ]

    sources = files(
        'src/plugin.vala',
        'src/register_plugin.vala',
        'src/mqtt_client.vala',
    )

    vapi_sources = files(
        'vapi/mosquitto.vapi',
    )

    vala_args = [
        '--vapidir', meson.current_source_dir() / 'vapi',
    ]

    c_args = [
        '-DG_LOG_DOMAIN="mqtt"',
        '-DGETTEXT_PACKAGE="dino"',
    ]

    lib_mqtt = shared_library('mqtt', sources + vapi_sources,
        name_prefix: '',
        c_args: c_args,
        vala_args: vala_args,
        dependencies: dependencies + [lib_mosquitto_link],
        install: true,
        install_dir: get_option('libdir') / get_option('plugindir'),
        install_rpath: default_install_rpath,
    )

    dep_mqtt = declare_dependency(
        link_with: lib_mqtt,
        include_directories: include_directories('.'),
    )

    summary('MQTT IoT/Event Plugin (mqtt)', dep_mqtt, section: 'Plugins')

else
    summary('MQTT IoT/Event Plugin (mqtt)', 'SKIPPED — libmosquitto not found', section: 'Plugins')
endif
