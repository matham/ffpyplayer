# -*- coding: utf-8 -*-

import ffpyplayer

extensions = [
    'sphinx.ext.autodoc',
    'sphinx.ext.todo',
    'sphinx.ext.coverage'
]

html_sidebars = {
    '**': [
        'about.html',
        'navigation.html',
        'relations.html',
        'searchbox.html',
        'sourcelink.html'
    ]
}

html_theme_options = {
    'github_button': 'true',
    'github_banner': 'true',
    'github_user': 'matham',
    'github_repo': 'ffpyplayer'
}

# The suffix of source filenames.
source_suffix = '.rst'

# The master toctree document.
master_doc = 'index'

# General information about the project.
project = u'FFPyPlayer'

# The short X.Y version.
version = ffpyplayer.__version__
# The full version, including alpha/beta/rc tags.
release = ffpyplayer.__version__

# List of patterns, relative to source directory, that match files and
# directories to ignore when looking for source files.
exclude_patterns = []

# The name of the Pygments (syntax highlighting) style to use.
pygments_style = 'sphinx'

# The theme to use for HTML and HTML Help pages.  See the documentation for
# a list of builtin themes.
html_theme = 'alabaster'

# Output file base name for HTML help builder.
htmlhelp_basename = 'FFPyPlayerdoc'

latex_elements = {}

latex_documents = [
  ('index', 'FFPyPlayer.tex', u'FFPyPlayer Documentation',
   u'Matthew Einhorn', 'manual'),
]

# One entry per manual page. List of tuples
# (source start file, name, description, authors, manual section).
man_pages = [
    ('index', 'FFPyPlayer', u'FFPyPlayer Documentation',
     [u'Matthew Einhorn'], 1)
]

# Grouping the document tree into Texinfo files. List of tuples
# (source start file, target name, title, author,
#  dir menu entry, description, category)
texinfo_documents = [
  ('index', 'FFPyPlayer', u'FFPyPlayer Documentation',
   u'Matthew Einhorn', 'FFPyPlayer', 'One line description of project.',
   'Miscellaneous'),
]
