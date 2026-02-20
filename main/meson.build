# Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

subdir('po')
dependencies = [
    dep_dino,
    dep_gee,
    dep_glib,
    dep_gmodule,
    dep_gstreamer,
    dep_gstreamer_app_core,
    dep_gtk4,
    dep_icu_uc,
    dep_json_glib,
    dep_libadwaita,
    dep_libsoup,
    dep_m,
    dep_qlite,
    dep_xmpp_vala,
    meson.get_compiler('vala').find_library('posix'),
]

if host_machine.system() != 'windows'
    dependencies += dep_dbusmenu
endif

have_x11 = dep_gtk4_x11.found() and dep_x11.found()
if have_x11
    dependencies += [dep_gtk4_x11, dep_x11]
endif

# Source files (platform-independent)
sources = files(
    'src/main.vala',
    'src/ui/add_conversation/add_conference_dialog.vala',
    'src/ui/add_conversation/add_contact_dialog.vala',
    'src/ui/add_conversation/add_groupchat_dialog.vala',
    'src/ui/add_conversation/room_browser_dialog.vala',
    'src/ui/add_conversation/contact_browser_dialog.vala',
    'src/ui/add_conversation/conference_details_fragment.vala',
    'src/ui/add_conversation/conference_list.vala',
    'src/ui/add_conversation/list_row.vala',
    'src/ui/add_conversation/roster_list.vala',
    'src/ui/add_conversation/select_contact_dialog.vala',
    'src/ui/add_conversation/select_jid_fragment.vala',
    'src/ui/add_conversation/user_search_dialog.vala',
    'src/ui/application.vala',
    'src/ui/bot_manager_dialog.vala',
    'src/ui/bot_create_dialog.vala',
    'src/ui/call_window/audio_settings_popover.vala',
    'src/ui/call_window/call_bottom_bar.vala',
    'src/ui/call_window/call_connection_details_window.vala',
    'src/ui/call_window/call_dialpad.vala',
    'src/ui/call_window/call_encryption_button.vala',
    'src/ui/call_window/call_window.vala',
    'src/ui/call_window/call_window_controller.vala',
    'src/ui/call_window/group_call_participant_list.vala',
    'src/ui/call_window/participant_widget.vala',
    'src/ui/call_window/video_settings_popover.vala',
    'src/ui/chat_input/audio_recorder.vala',
    'src/ui/chat_input/voice_recorder_popover.vala',
    'src/ui/chat_input/video_recorder.vala',
    'src/ui/chat_input/video_recorder_popover.vala',
    'src/ui/chat_input/chat_input_controller.vala',
    'src/ui/chat_input/chat_text_view.vala',
    'src/ui/chat_input/encryption_button.vala',
    'src/ui/chat_input/occupants_tab_completer.vala',
    'src/ui/chat_input/smiley_converter.vala',
    'src/ui/chat_input/sticker_chooser.vala',
    'src/ui/chat_input/view.vala',
    'src/ui/contact_details/permissions_provider.vala',
    'src/ui/contact_details/settings_provider.vala',
    'src/ui/conversation_content_view/audio_player_widget.vala',
    'src/ui/conversation_content_view/video_player_widget.vala',
    'src/ui/conversation_content_view/call_widget.vala',
    'src/ui/conversation_content_view/chat_state_populator.vala',
    'src/ui/conversation_content_view/content_populator.vala',
    'src/ui/conversation_content_view/conversation_item_skeleton.vala',
    'src/ui/conversation_content_view/conversation_view.vala',
    'src/ui/conversation_content_view/date_separator_populator.vala',
    'src/ui/conversation_content_view/file_default_widget.vala',
    'src/ui/conversation_content_view/file_image_widget.vala',
    'src/ui/conversation_content_view/file_transmission_progress.vala',
    'src/ui/conversation_content_view/file_widget.vala',
    'src/ui/conversation_content_view/item_actions.vala',
    'src/ui/conversation_content_view/message_widget.vala',
    'src/ui/conversation_content_view/quote_widget.vala',
    'src/ui/conversation_content_view/url_preview_widget.vala',
    'src/ui/conversation_content_view/reactions_widget.vala',
    'src/ui/conversation_content_view/subscription_notification.vala',
    'src/ui/conversation_content_view/expiry_notification.vala',
    'src/ui/conversation_content_view/unread_indicator_populator.vala',
    'src/ui/conversation_content_view/status_populator.vala',
    'src/ui/conversation_details.vala',
    'src/ui/conversation_selector/conversation_selector.vala',
    'src/ui/conversation_selector/conversation_selector_row.vala',
    'src/ui/conversation_titlebar/call_entry.vala',
    'src/ui/conversation_titlebar/menu_entry.vala',
    'src/ui/conversation_titlebar/occupants_entry.vala',
    'src/ui/conversation_titlebar/search_entry.vala',
    'src/ui/conversation_view.vala',
    'src/ui/conversation_view_controller.vala',
    'src/ui/file_send_overlay.vala',
    'src/ui/global_search.vala',
    'src/ui/main_window.vala',
    'src/ui/main_window_controller.vala',
    'src/ui/muc_admin_dialog.vala',
    'src/ui/notifier_freedesktop.vala',
    'src/ui/notifier_gnotifications.vala',
    'src/ui/occupant_menu/list.vala',
    'src/ui/occupant_menu/list_row.vala',
    'src/ui/occupant_menu/view.vala',
    'src/ui/util/accounts_combo_box.vala',
    'src/ui/util/config.vala',
    'src/ui/util/data_forms.vala',
    'src/ui/util/file_metadata_providers.vala',
    'src/ui/util/helper.vala',
    'src/ui/util/location_manager.vala',
    'src/ui/util/preference_group.vala',
    'src/ui/util/ui_timing.vala',
    'src/ui/util/size_request_box.vala',
    'src/ui/util/sizing_bin.vala',
    'src/ui/sticker_pack_import_dialog.vala',
    'src/ui/sticker_pack_folder_import_dialog.vala',
    'src/ui/sticker_manager.vala',
    'src/ui/widgets/avatar_picture.vala',
    'src/ui/widgets/date_separator.vala',
    'src/ui/widgets/fixed_ratio_picture.vala',
    'src/ui/widgets/natural_size_increase.vala',
    'src/view_model/account_details.vala',
    'src/view_model/conversation_details.vala',
    'src/view_model/preferences_dialog.vala',
    'src/view_model/preferences_row.vala',
    'src/windows/preferences_window/account_preferences_subpage.vala',
    'src/windows/preferences_window/accounts_preferences_page.vala',
    'src/windows/preferences_window/add_account_dialog.vala',
    'src/windows/preferences_window/certificate_warning_dialog.vala',
    'src/windows/preferences_window/change_password_dialog.vala',
    'src/windows/preferences_window/contacts_preferences_page.vala',
    'src/windows/preferences_window/encryption_preferences_page.vala',
    'src/windows/preferences_window/general_preferences_page.vala',
    'src/windows/preferences_window/preferences_dialog.vala',
    'src/windows/conversation_details.vala',
)

# Platform-specific systray implementation
if host_machine.system() == 'windows'
    sources += files('src/ui/systray_windows.vala')
else
    sources += files('src/ui/systray.vala')
endif

sources += gnome.compile_resources(
    'resources',
    'data/gresource.xml',
    source_dir: 'data',
)

c_args = [
    '-DG_LOG_DOMAIN="dino"',
    '-DGETTEXT_PACKAGE="dino"',
    '-DLOCALE_INSTALL_DIR="@0@"'.format(get_option('prefix') / get_option('localedir')),
]
vala_args = [
    '--vapidir=' + (meson.current_source_dir() / 'vapi'),
]
message('VAPI DIR: ' + (meson.current_source_dir() / 'vapi'))
if have_x11
    vala_args += ['-D', 'HAVE_X11']
endif
if dep_gtk4.version() == 'unknown' or dep_gtk4.version().version_compare('>=4.6')
    vala_args += ['-D', 'GTK_4_6']
endif
if dep_gtk4.version() == 'unknown' or dep_gtk4.version().version_compare('>=4.8')
    vala_args += ['-D', 'GTK_4_8']
endif
if dep_gtk4.version() == 'unknown' or dep_gtk4.version().version_compare('>=4.12')
    vala_args += ['-D', 'GTK_4_12']
endif
if dep_gtk4.version() == 'unknown' or dep_gtk4.version().version_compare('>=4.14')
    vala_args += ['-D', 'GTK_4_14']
    sources += files('src/ui/conversation_content_view/file_transmission_progress.c')
endif

# Compatibility wrapper for deprecated GValueArray (used by GStreamer level element)
sources += files('src/ui/chat_input/gva_compat.c')

# Voice message noise suppression (optional, uses webrtc-audio-processing-2)
if dep_webrtc_audio_processing.found()
    voice_msg_ns_deps = [dep_glib, dep_gstreamer, dep_webrtc_audio_processing]
    voice_msg_ns_cpp_args = c_args
    if dep_webrtc_audio_processing.version().version_compare('>=2.0')
        voice_msg_ns_cpp_args += ['-DWITH_VOICE_PROCESSOR', '-DWEBRTC2']
    elif dep_webrtc_audio_processing.version().version_compare('>=1.0')
        voice_msg_ns_cpp_args += ['-DWITH_VOICE_PROCESSOR', '-DWEBRTC1']
    endif
    lib_voice_msg_ns = static_library('voice-msg-ns',
        files('src/ui/chat_input/voice_msg_ns.cpp'),
        cpp_args: voice_msg_ns_cpp_args,
        dependencies: voice_msg_ns_deps,
        install: false,
    )
    dependencies += declare_dependency(link_with: lib_voice_msg_ns)
else
    # Build stub version without webrtc-audio-processing
    lib_voice_msg_ns = static_library('voice-msg-ns',
        files('src/ui/chat_input/voice_msg_ns.cpp'),
        cpp_args: c_args,
        dependencies: [dep_glib, dep_gstreamer],
        install: false,
    )
    dependencies += declare_dependency(link_with: lib_voice_msg_ns)
endif

if dep_libadwaita.version() == 'unknown' or dep_libadwaita.version().version_compare('>=1.4')
    vala_args += ['-D', 'Adw_1_4']
endif
if meson.get_compiler('vala').version().version_compare('>=0.56.5') and meson.get_compiler('vala').version().version_compare('<0.58')
    vala_args += ['-D', 'VALA_0_56_GREATER_5']
endif
if meson.get_compiler('vala').version().version_compare('>=0.56.11') and meson.get_compiler('vala').version().version_compare('<0.58')
    vala_args += ['-D', 'VALA_0_56_GREATER_11']
endif
if meson.get_compiler('vala').version().version_compare('=0.56.11')
    vala_args += ['-D', 'VALA_0_56_11']
endif
if meson.get_compiler('vala').version().version_compare('=0.56.12')
    vala_args += ['-D', 'VALA_0_56_12']
endif

# Windows-specific: embed icon in .exe and use GUI subsystem (no terminal window)
extra_link_args = []
extra_objects = []
if host_machine.system() == 'windows'
    # Use GUI subsystem so double-clicking dinox.exe doesn't open a console window
    extra_link_args += ['-mwindows']

    # Compile Windows resource file (.rc) to embed the app icon in the .exe
    windows_mod = import('windows')
    win_res = windows_mod.compile_resources(
        'data/dinox.rc',
        depend_files: files('data/dinox.ico'),
    )
    sources += win_res
endif

exe_dino = executable('dinox', sources, c_args: c_args, vala_args: vala_args, link_args: extra_link_args, dependencies: dependencies, install: true, install_rpath: default_install_rpath)

# Install app icons (PNG sizes for better systray support)
install_data('data/icons/hicolor/16x16/apps/im.github.rallep71.DinoX.png', install_dir: get_option('datadir') / 'icons/hicolor/16x16/apps')
install_data('data/icons/hicolor/32x32/apps/im.github.rallep71.DinoX.png', install_dir: get_option('datadir') / 'icons/hicolor/32x32/apps')
install_data('data/icons/hicolor/48x48/apps/im.github.rallep71.DinoX.png', install_dir: get_option('datadir') / 'icons/hicolor/48x48/apps')
install_data('data/icons/hicolor/128x128/apps/im.github.rallep71.DinoX.png', install_dir: get_option('datadir') / 'icons/hicolor/128x128/apps')
install_data('data/icons/hicolor/256x256/apps/im.github.rallep71.DinoX.png', install_dir: get_option('datadir') / 'icons/hicolor/256x256/apps')
install_data('data/icons/hicolor/512x512/apps/im.github.rallep71.DinoX.png', install_dir: get_option('datadir') / 'icons/hicolor/512x512/apps')

# Install metadata and desktop files
install_data('data/im.github.rallep71.DinoX.appdata.xml', install_dir: get_option('datadir') / 'metainfo')
install_data('data/im.github.rallep71.DinoX.desktop', install_dir: get_option('datadir') / 'applications')
install_data('data/im.github.rallep71.DinoX.service', install_dir: get_option('datadir') / 'dbus-1/services')
