# Desktop file
desktop_file = i18n.merge_file(
  input: 'org.gnome.gDiagram.desktop.in',
  output: 'org.gnome.gDiagram.desktop',
  type: 'desktop',
  po_dir: join_paths(meson.project_source_root(), 'po'),
  install: true,
  install_dir: join_paths(get_option('datadir'), 'applications'),
)

# AppStream metainfo
install_data(
  'org.gnome.gDiagram.metainfo.xml',
  install_dir: join_paths(get_option('datadir'), 'metainfo'),
)

# GSettings schema
install_data(
  'org.gnome.gDiagram.gschema.xml',
  install_dir: join_paths(get_option('datadir'), 'glib-2.0', 'schemas'),
)

# Icons
install_data(
  'icons/hicolor/scalable/apps/org.gnome.gDiagram.svg',
  install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', 'scalable', 'apps'),
)

# GtkSourceView language spec
install_data(
  'lang/plantuml.lang',
  install_dir: join_paths(get_option('datadir'), 'gtksourceview-5', 'language-specs'),
)
