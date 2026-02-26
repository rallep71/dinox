# MQTT Plugin for DinoX
#
# Optional plugin — requires libmosquitto (client library).
# If libmosquitto is not available, the plugin is skipped.
#
# Platform notes:
#   Linux:   apt install libmosquitto-dev
#   MSYS2:   pacman -S mingw-w64-x86_64-mosquitto
#   Flatpak: Built from source (see im.github.rallep71.DinoX.json)

plugin_mqtt_opt = get_option('plugin-mqtt')

# Step 1: Detect libmosquitto via pkg-config
dep_mosquitto_check = dependency('libmosquitto',
    required: plugin_mqtt_opt.enabled(),
)

if dep_mosquitto_check.found() and plugin_mqtt_opt.allowed()

    # Step 2: Link via C compiler (not valac --pkg) because there is
    #         no system Vala VAPI. Our custom vapi/mosquitto.vapi is
    #         added to sources instead.
    cc = meson.get_compiler('c')
    lib_mosquitto_link = cc.find_library('mosquitto')

    dependencies = [
        dep_dino,
        dep_gee,
        dep_gio,
        dep_glib,
        dep_gmodule,
        dep_gtk4,
        dep_libadwaita,
        dep_qlite,
        dep_xmpp_vala,
    ]

    sources = files(
        'src/plugin.vala',
        'src/register_plugin.vala',
        'src/mqtt_client.vala',
        'src/server_detector.vala',
        'src/settings_page.vala',
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

    summary('MQTT IoT/Event Plugin (mqtt)', true, section: 'Plugins')

else
    if plugin_mqtt_opt.enabled()
        error('MQTT plugin was explicitly enabled but libmosquitto was not found.\n' + \
              'Install: apt install libmosquitto-dev (Linux) or pacman -S mingw-w64-x86_64-mosquitto (MSYS2)')
    endif
    summary('MQTT IoT/Event Plugin (mqtt)', false, section: 'Plugins')
endif
