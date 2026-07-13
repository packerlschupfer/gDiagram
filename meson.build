project('gdiagram', ['c', 'vala'],
  version: '0.1.0',
  meson_version: '>= 0.60.0',
  default_options: [
    'warning_level=2',
    'werror=false',
  ]
)

app_id = 'org.gnome.gDiagram'

i18n = import('i18n')
gnome = import('gnome')

# Dependencies
gtk4_dep = dependency('gtk4', version: '>= 4.10')
libadwaita_dep = dependency('libadwaita-1', version: '>= 1.4')
gtksourceview_dep = dependency('gtksourceview-5', version: '>= 5.0')
gee_dep = dependency('gee-0.8')
libgvc_dep = dependency('libgvc')
librsvg_dep = dependency('librsvg-2.0')
cairo_dep = dependency('cairo')
soup_dep = dependency('libsoup-3.0')
json_dep = dependency('json-glib-1.0')
libsecret_dep = dependency('libsecret-1')
math_dep = meson.get_compiler('c').find_library('m', required: false)

# Detect whether Graphviz gvRenderData uses size_t* (upstream/patched) or unsigned int* (system)
cc = meson.get_compiler('c')
graphviz_size_t = cc.compiles('''
  #include <gvc.h>
  #include <stddef.h>
  int main(void) {
    size_t len;
    int (*fn)(GVC_t*, graph_t*, const char*, char**, size_t*) = gvRenderData;
    (void)fn; (void)len;
    return 0;
  }
''', dependencies: libgvc_dep, name: 'gvRenderData uses size_t*')

# Configuration
conf = configuration_data()
conf.set_quoted('APP_ID', app_id)
conf.set_quoted('APP_NAME', 'gDiagram')
conf.set_quoted('VERSION', meson.project_version())

# A build identifier for `--version`: see src/config.vala.in. `git describe` identifies
# the content, and the committer date moves on every amend (the author date is pinned).
git_prog = find_program('git', required: false)
build_id = 'unknown'
build_date = 'unknown'
if git_prog.found()
  # --long: without it `git describe` prints just "v0.1.0" whenever HEAD is the release
  # tag — which is every release build — and that tag moves, so it identifies nothing.
  # With it the hash is always there: "v0.1.0-0-g3c03768d7394".
  git_desc = run_command(git_prog, '-C', meson.project_source_root(),
                         'describe', '--always', '--dirty', '--abbrev=12', '--long', check: false)
  if git_desc.returncode() == 0
    build_id = git_desc.stdout().strip()
  endif
  git_date = run_command(git_prog, '-C', meson.project_source_root(),
                         'log', '-1', '--format=%cd', '--date=format:%Y-%m-%d', check: false)
  if git_date.returncode() == 0
    build_date = git_date.stdout().strip()
  endif
endif
conf.set_quoted('BUILD_ID', build_id)
conf.set_quoted('BUILD_DATE', build_date)
conf.set_quoted('GETTEXT_PACKAGE', meson.project_name())
conf.set_quoted('LOCALEDIR', join_paths(get_option('prefix'), get_option('localedir')))
conf.set_quoted('DATADIR', join_paths(get_option('prefix'), get_option('datadir')))

config_file = configure_file(
  input: 'src/config.vala.in',
  output: 'config.vala',
  configuration: conf
)

# Subdirectories
subdir('data')
subdir('src')
subdir('po')
subdir('tests')

gnome.post_install(
  glib_compile_schemas: true,
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)
