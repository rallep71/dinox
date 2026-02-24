dependencies = [
    dep_dino,
    dep_gee,
    dep_glib,
    dep_gmodule,
    dep_libsoup,
    dep_qlite,
    dep_xmpp_vala,
    dep_crypto_vala,
]
sources = files(
    'src/file_provider.vala',
    'src/file_sender.vala',
    'src/plugin.vala',
    'src/register_plugin.vala',
)

vala_args = [
    '-D', 'SOUP_3_0',
    '--header', meson.current_build_dir() / 'http-files.h',
    '--internal-vapi', meson.current_build_dir() / 'http-files-internal.vapi',
    '--internal-header', meson.current_build_dir() / 'http-files-internal.h',
]
lib_http_files = shared_library('http-files', sources, name_prefix: '', vala_args: vala_args, dependencies: dependencies, install: true, install_dir: get_option('libdir') / get_option('plugindir'), install_rpath: default_install_rpath)
dep_http_files = declare_dependency(link_with: lib_http_files, include_directories: include_directories('.'))
summary('HTTP file upload (http-files)', dep_http_files.found(), bool_yn: true, section: 'Plugins')

vapi_http_files_internal = custom_target('http-files-internal-vapi', command: [find_program('touch'), meson.current_build_dir() / 'http-files-internal.vapi'], output: ['http-files-internal.vapi'], depends: lib_http_files)
dep_http_files_internal = declare_dependency(link_args: [lib_http_files.full_path()], include_directories: include_directories('.', 'src'), sources: [vapi_http_files_internal])

test_sources = [
    'tests/common.vala',
    'tests/testcase.vala',
    'tests/http_files_test.vala',
]
test_vala_args = [
    '-D', 'SOUP_3_0',
]
test_c_args = ['-DG_LOG_DOMAIN="http-files-test"', '-include', 'http-files-internal.h']

exe_http_files_test = executable('http-files-test', test_sources, c_args: test_c_args, vala_args: test_vala_args, dependencies: dependencies + dep_http_files_internal, build_rpath: '$ORIGIN', install: false)
test('Tests for http-files', exe_http_files_test)
