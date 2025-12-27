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

# Configuration
conf = configuration_data()
conf.set_quoted('APP_ID', app_id)
conf.set_quoted('APP_NAME', 'gDiagram')
conf.set_quoted('VERSION', meson.project_version())
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
# Temporarily disable tests until they are properly implemented
# subdir('tests')

gnome.post_install(
  glib_compile_schemas: true,
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)
