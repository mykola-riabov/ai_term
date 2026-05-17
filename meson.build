project(
    'Aiterm', 'd',
    version: '0.1.0',
    license: 'MPL-2.0',
    meson_version: '>= 0.56'
)

compiler = meson.get_compiler('d')
if compiler.get_id() == 'llvm'
  d_extra_args = ['-vcolumns']
  # gtkd/vted are shared D libs — must use shared Phobos (see rt/sections_elf_shared)
  d_link_args = ['-link-defaultlib-shared=true']
else
  d_extra_args = []
  d_link_args = []
endif

project_id = 'com.aiterm.Aiterm'
project_name = meson.project_name()

gnome = import('gnome')
i18n = import('i18n')

prefix = get_option('prefix')
bindir = prefix / get_option('bindir')
datadir = prefix / get_option('datadir')
# Data paths must stay "aiterm" — constants.d and GSettings use com.aiterm.Aiterm / aiterm/
pkgdatadir = datadir / 'aiterm'
schemadir = datadir / 'glib-2.0' / 'schemas'
iconsdir = datadir / 'icons' / 'hicolor'
appdir = datadir / 'applications'

aiterm_sources = [
    'source/gx/gtk/actions.d',
    'source/gx/gtk/cairo.d',
    'source/gx/gtk/clipboard.d',
    'source/gx/gtk/color.d',
    'source/gx/gtk/dialog.d',
    'source/gx/gtk/resource.d',
    'source/gx/gtk/settings.d',
    'source/gx/gtk/threads.d',
    'source/gx/gtk/util.d',
    'source/gx/gtk/vte.d',
    'source/gx/gtk/x11.d',
    'source/gx/i18n/l10n.d',
    'source/gx/aiterm/bookmark/bmchooser.d',
    'source/gx/aiterm/bookmark/bmeditor.d',
    'source/gx/aiterm/bookmark/bmtreeview.d',
    'source/gx/aiterm/modern/store.d',
    'source/gx/aiterm/modern/aiproviders.d',
    'source/gx/aiterm/modern/llm.d',
    'source/gx/aiterm/modern/quickbar.d',
    'source/gx/aiterm/modern/aichat.d',
    'source/gx/aiterm/modern/sshhub.d',
    'source/gx/aiterm/modern/prompthub.d',
    'source/gx/aiterm/modern/chathub.d',
    'source/gx/aiterm/modern/prefpage.d',
    'source/gx/aiterm/bookmark/manager.d',
    'source/gx/aiterm/prefeditor/advdialog.d',
    'source/gx/aiterm/prefeditor/bookmarkeditor.d',
    'source/gx/aiterm/prefeditor/common.d',
    'source/gx/aiterm/prefeditor/prefdialog.d',
    'source/gx/aiterm/prefeditor/profileeditor.d',
    'source/gx/aiterm/prefeditor/titleeditor.d',
    'source/gx/aiterm/terminal/actions.d',
    'source/gx/aiterm/terminal/activeprocess.d',
    'source/gx/aiterm/terminal/advpaste.d',
    'source/gx/aiterm/terminal/exvte.d',
    'source/gx/aiterm/terminal/layout.d',
    'source/gx/aiterm/terminal/monitor.d',
    'source/gx/aiterm/terminal/password.d',
    'source/gx/aiterm/terminal/regex.d',
    'source/gx/aiterm/terminal/search.d',
    'source/gx/aiterm/terminal/terminal.d',
    'source/gx/aiterm/terminal/util.d',
    'source/gx/aiterm/application.d',
    'source/gx/aiterm/appwindow.d',
    'source/gx/aiterm/closedialog.d',
    'source/gx/aiterm/cmdparams.d',
    'source/gx/aiterm/colorschemes.d',
    'source/gx/aiterm/common.d',
    'source/gx/aiterm/constants.d',
    'source/gx/aiterm/customtitle.d',
    'source/gx/aiterm/encoding.d',
    'source/gx/aiterm/preferences.d',
    'source/gx/aiterm/session.d',
    'source/gx/aiterm/shortcuts.d',
    'source/gx/aiterm/sidebar.d',
    'source/gx/util/array.d',
    'source/gx/util/path.d',
    'source/gx/util/string.d',
    'source/secret/Collection.d',
    'source/secret/Item.d',
    'source/secret/Prompt.d',
    'source/secret/Schema.d',
    'source/secret/SchemaAttribute.d',
    'source/secret/Secret.d',
    'source/secret/Service.d',
    'source/secret/Value.d',
    'source/secretc/secret.d',
    'source/secretc/secrettypes.d',
    'source/x11/X.d',
    'source/x11/Xlib.d',
    'source/app.d'
]

sources_dir = include_directories('source/')

# Dependencies
gtkd_dep = dependency('gtkd-3', version: '>=3.10.0')
vted_dep = dependency('vted-3', version: '>=3.10.0')
xlib_dep = dependency('x11')
libsecret_dep = dependency('libsecret-1', required: false)

subdir('po')
subdir('data')

# Build & Test
executable('aiterm',
    [aiterm_sources, gresource],
    include_directories : sources_dir,
    dependencies : [gtkd_dep,
                    vted_dep,
                    xlib_dep,
                    libsecret_dep],
    d_args: d_extra_args,
    d_module_versions: ['StdLoggerDisableTrace'],
    link_args: d_link_args,
    install : true
)

aiterm_test_exe = executable('aiterm_test',
    [aiterm_sources],
    include_directories : [sources_dir],
    dependencies : [gtkd_dep,
                    vted_dep,
                    xlib_dep],
    d_args: d_extra_args,
    link_args: d_link_args,
    d_unittest: true
)
test('aiterm_test', aiterm_test_exe)

meson.add_install_script('meson_post_install.py')
