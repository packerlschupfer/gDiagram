# Test suite
test_deps = [
  gtk4_dep,
  libadwaita_dep,
  gtksourceview_dep,
  gee_dep,
  libgvc_dep,
  librsvg_dep,
  cairo_dep,
  soup_dep,
  json_dep,
]

# Create a static library with common test sources to avoid duplicate compilation
test_common_sources = files(
  '../src/core/parser/Lexer.vala',
  '../src/core/parser/Token.vala',
  '../src/core/parser/Parser.vala',
  '../src/core/ast/DiagramNode.vala',
  '../src/core/Document.vala',
)

test_common_lib = static_library('test_common',
  test_common_sources,
  config_file,
  dependencies: test_deps,
  vala_args: ['--target-glib=2.74']
)

# Lexer tests
lexer_test = executable('lexer_test',
  'lexer_test.vala',
  dependencies: test_deps,
  link_with: test_common_lib,
  vala_args: ['--target-glib=2.74']
)

test('Lexer tests', lexer_test)

# Parser tests
parser_test = executable('parser_test',
  'parser_test.vala',
  dependencies: test_deps,
  link_with: test_common_lib,
  vala_args: ['--target-glib=2.74']
)

test('Parser tests', parser_test)

# Document tests
document_test = executable('document_test',
  'document_test.vala',
  dependencies: test_deps,
  link_with: test_common_lib,
  vala_args: ['--target-glib=2.74']
)

test('Document tests', document_test)
