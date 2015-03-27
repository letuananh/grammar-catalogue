## The DELPH-IN Grammar Catalogue Script
 
This script scans a grammar directory and generates a summary of
some metrics of the grammar, as well accumulating additional
metadata. This summary is intended to be used for the Grammar
Catalogue wiki page at http://moin.delph-in.net/GrammarCatalogue,
but it can also output in LaTeX or HTML formats.

See LICENSE for copyright information.

### Dependencies and configuration

* subversion must be installed for svn metrics
* LOGON must be installed and LOGONROOT set for grammar metrics
* METADATA file must exist in grammar root directory for other info
* canonical.bib or citation.bib must exist in grammar directory for
  citation data if it is not defined in METADATA

### Usage:

    $ ./create-catalogue-entry.sh -h
    Usage:
      create-catalogue-entry.sh [OPTIONS] [PATH]
    Options:
      -h|--help  : display this help message
      -d|--debug : print debug messages
      -q|--quiet : suppress warning messages
      -l|--latex : format output for LaTeX
      -w|--www   : format output as HTML
    Arguments:
      PATH: (optional) create catalogue entry for grammar at PATH
            or the current directory if unspecified


PATH is the top-level grammar directory for the grammar to catalogue.
If unspecified, PATH is assumed to be the current directory. The top-
level grammar directory is where the METADATA file should exist, as
well as the canonical.bib and the lkb/ directory. Further, the
directory should be under SVN version control for the extraction of
version metrics.

Given a SVN-versioned grammar directory with completed METADATA and
canonical.bib files, run this command on that directory. The catalogue
information (in MoinMoin wiki format by default, or in LaTeX or HTML
via the `-l` or `-w` options) will be printed to standard output
(STDOUT). This output can then be copied elsewhere.

### Acknowledgments

The following people have contributed to the development of the script:

Code:
* Francis Bond
* Dan Flickinger
* Michael Wayne Goodman

METADATA specification:
* Emily Bender
* Antske Fokkens

Comments and ideas:
* Joshua Crowgey
* Petter Haugereid
* Sanghoun Song
* David Wax

