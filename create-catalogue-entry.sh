#!/bin/bash

##
## create-catalogue-entry.sh
##
##    Automatically extract grammar info and format it for the Grammar
##    Catalogue wiki at http://wiki.delph-in.net/moin/GrammarCatalogue,
##    for LaTeX, or for HTML.
##
## Author: Michael Wayne Goodman (goodmami@uw.edu)
## Contributors: Francis Bond and Dan Flickinger (LISP function);
##               Emily Bender and Antske Fokkens (METADATA specification);
##               Joshua Crowgey, Petter Haugereid, Sanghoun Song, and
##               David Wax (comments and ideas)
##
## License: MIT; See the LICENSE file for terms.
##
## Requirements:
##   * subversion must be installed for svn metrics
##   * LOGON must be installed and LOGONROOT set for grammar metrics
##   * METADATA file must exist in grammar root directory for other info
##   * canonical.bib or citation.bib must exist in grammar directory for
##     citation data if it is not defined in METADATA
##

####################
## INITIALIZATION ##
####################

pub_date=`date --rfc-3339=date`
formatter=moinmoin

### LOGGING ###

verbosity=2 # default to show warnings
SILENT_LVL=0
ERR_LVL=1
WRN_LVL=2
DBG_LVL=3
#INF_LVL=4  # probably not necessary

error() { log $ERR_LVL "ERROR: $1"; }
warn() { log $WRN_LVL "WARNING: $1"; }
debug() { log $DBG_LVL "DEBUG: $1"; }
log() {
    if [ $verbosity -ge $1 ]; then
        # Expand escaped characters, wrap at 70 chars, indent wrapped lines
        echo -e "$2" | fold -w70 -s | sed '2~1s/^/  /' >&2
    fi
}


### COMMAND LINE ARGUMENTS ###

usage() {
    echo "Usage:"
    echo "  create-catalogue-entry.sh [OPTIONS] [PATH]"
    echo "Options:"
    echo "  -h|--help  : display this help message"
    echo "  -d|--debug : print debug messages"
    echo "  -q|--quiet : suppress warning messages"
    echo "  -l|--latex : format output for LaTeX"
    echo "  -w|--www   : format output as HTML"
    echo "Arguments:"
    echo "  PATH: (optional) create catalogue entry for grammar at PATH"
    echo "        or the current directory if unspecified"
    exit 1
}

longopts="help debug quiet latex www"
shortopts="hdqlw"

set -- `getopt -n$0 -u --longoptions="$longopts" --options="$shortopts" -- "$@"` || usage

while [ $# -gt 0 ]; do
    case "$1" in
       --help|-h) usage; shift ;;
       --debug|-d) verbosity=$DBG_LVL; shift ;;
       --quiet|-q) verbosity=$ERR_LVL; shift ;;
       --latex|-l) formatter=latex; shift ;;
       --www|-w) formatter=html; shift ;;
       --) shift; break ;;
    esac
done
args="$@"

debug "Formatter: $formatter"
debug "Verbosity: $verbosity"

# attempt to use the current directory if one is not provided
# need to "cd ...; pwd" to resolve relative paths
dir=`cd ${args[0]:-'.'}; pwd`
debug "Grammar directory: $dir"

##################
## EXTRACT DATA ##
##################

# Always display this notification:
echo "NOTE: Now attempting to extract data for the catalogue entry." >&2
echo "      This could take several minutes, so please be patient." >&2

### METADATA FILE ###

if [ -e $dir/METADATA ]; then
    source $dir/METADATA
else
    warn "METADATA file not found!"
fi

# get shortname if not defined
if [ ! "$SHORT_GRAMMAR_NAME" ]; then
    SHORT_GRAMMAR_NAME=`basename $dir`
fi

### VERSION CONTROL INFO ###

if [ -d "$dir"/.svn ]
then
    debug "Subversion working copy found."
    # default is svn of grammar directory. get URL to compare later
    local_url=`svn info $dir | grep "^URL:" | grep -o "\b\w\+://\S\+"`
    debug "URL for local SVN repository: $local_url"
    # if VCS is defined in METADATA, get info from there instead
    if [ "$VCS" ]; then
        # filter SVN commands to get URL (e.g. "svn co URL")
        vcs_url=`echo $VCS | grep -o "\b\w\+://\S\+"`
        debug "URL for SVN repository given in METADATA file: $vcs_url"
        if [ "$local_url" != "$vcs_url" ]; then
            warn "Repository URL provided in METADATA file differs from that of the local checkout. Since the local data is used for calculating various grammar metrics, fields of the catalogue entry may be inaccurate."
        fi
    else
        vcs_url="$local_url"
    fi
    debug "Proceeding with the following SVN URL: $vcs_url"
    svn_stats=`svn info $vcs_url | grep "^\(URL:\|Revision:\|Last Changed\)"`
    if [ ! "$VCS" ]; then
        VCS=`echo "$svn_stats" | grep "^URL:" | sed 's/^URL: //'`
    fi
    REV_LATEST=`echo "$svn_stats" | grep "^Revision:" | sed 's/^Revision: //'`
    REV_CHANGED=`echo "$svn_stats" | grep "^Last Changed Rev:" | sed 's/^Last Changed Rev: //'`
    debug "Version control URL/command: $VCS"
    debug "Latest revision from repository: $REV_LATEST"
# elif add support for other version control systems here
fi

### GRAMMAR VERSION ###

version_lsp=`ls $dir/Version.l*sp`
if [ $? -ne 0 ]; then
    warn "Failed to find version file in grammar directory."
else
    debug "Version file: $version_lsp"
fi
# don't try to extract a version if an explicit one is given
if [[ ( ! "$LATEST_RELEASE" ) && ( -e $version_lsp ) ]]; then
    LATEST_RELEASE=`grep "\*grammar-version\*" $version_lsp | sed 's/^.*\* "[^(]\+(\([^)]\+\)).*/\1/'`
fi
debug "Latest release: $LATEST_RELEASE"
# Now interpret the date string if we have one
if [ "$LATEST_RELEASE" ]; then
    # Various date robustness transformations:
    release_date=`echo $LATEST_RELEASE | sed 's/_.*$//'` # remove time
    if [ ${#release_date} == 4 ]; then
      release_date="${release_date}01" # only year/month, add day
    fi
    # And convert to a standard date format
    release_date=`date --date="$release_date" --rfc-3339=date`
    # if date conversion succeeded, use it
    if [ $? -eq 0 ]; then
        LATEST_RELEASE="$release_date"
        debug "Latest release interpretted as: $LATEST_RELEASE"
    fi
fi

### BIBLIOGRAPHIC INFORMATION ###

# citations (defined in METADATA or pulled from .bib file)
if [[ ! ( "$BIB_URL" || "$PDF_URL" || "$CITE" ) ]]; then
    debug "No bibliographical details found in METADATA. Attempting to extract from .bib file."
    # .bib file must be called one of the following
    if [ -e "$dif/canonical.bib" ]; then
        CITATION=`cat $dir/canonical.bib`
    elif [ -e "$dir/citation.bib" ]; then
        CITATION=`cat $dir/citation.bib`
    fi
else
    CITATION="$CITE"
    if [ "$BIB_URL" ]; then
	case "$formatter" in
	    moinmoin)
		CITATION="$CITATION ([$BIB_URL .bib])"
		;;
	    html)
		CITATION="$CITATION (<a href='${BIB_URL}'>.bib</a>)"
		;;
	esac
    fi
    if [ "$PDF_URL" ]; then
	case "$formatter" in
	    moinmoin)
		CITATION="$CITATION ([$PDF_URL .pdf])"
		;;
	    html)
		CITATION="$CITATION (<a href='${PDF_URL}'>.pdf</a>)"
		;;
	esac
    fi
fi
debug "Citation: $CITATION"

### GRAMMAR METRICS ###

# get_meta calls a lisp function to get grammar metrics (number of types,
# features, etc). It requires writing to a file to avoid all of the lisp
# noise from loading the grammar, etc.
get_meta() {
    unset DISPLAY;
    unset LUI;
    
    grammardir=$1
    outfile=$2
    
    { 
     cat 2>&1 <<- LISP
      ;(load "$lkbdir/src/general/loadup")
      ;(compile-system "lkb" :force t)
      ;;; Load the grammar
      (lkb::read-script-file-aux  "$grammardir/lkb/script")
      (in-package :lkb)
      ;;; open the outputfile
      (with-open-file (stream "$outfile"
    		 :direction :output :if-exists :supersede
    		 :if-does-not-exist :create)
      ;(format stream "Grammar Path: ~A~%" "$grammardir")
      (format stream "LEXICAL_ITEMS=~A~%" 
          (length  (collect-psort-ids lkb::*lexicon*)))
    ;;(length (lex-words *lexicon*)) gives a smaller number quicker
      (format stream "LEXICAL_RULES=~A~%" 
          (hash-table-count  *lexical-rules*))
      (format stream "GRAMMAR_RULES=~A~%" 
          (hash-table-count  *rules*))
      (format stream "FEATURES=~A~%" 
          (length (remove-duplicates 
              (loop for elem in (ltype-descendants (get-type-entry *toptype*))
               append (ltype-appfeats elem)))))
      (format stream "TYPES_WITH_GLB=~A~%" 
          (length  *type-names*)))
      (format t "~%All Done!~%")
      (excl:exit)
LISP
    } | ${LOGONROOT}/bin/logon --binary -I base 2>/dev/null >/dev/null
}

grammar_metrics=$(mktemp "$(basename $0).XXXXXX")
debug "Attempting to get grammar metrics by loading the grammar with the LKB. Temporary file created: $grammar_metrics"
get_meta "$dir" "$grammar_metrics"
source "$grammar_metrics"
rm -f "$grammar_metrics"
debug "LKB process completed. Temporary file deleted."

######################
## FORMAT AND PRINT ##
######################

# Initialize formatting options
case "$formatter" in
    moinmoin)
        # Default formatting for Moinmoin wiki
        cs="||" # column start
        cm="||" # column delimiter (middle)
        cmn=$cm # column delimiter for numbers
        ce="||" # column end
        table_header="$cs [#$SHORT_GRAMMAR_NAME $GRAMMAR_NAME ($SHORT_GRAMMAR_NAME)] $cm $LANGUAGE_NAME $cm $MAINTAINER $ce\n\n== $GRAMMAR_NAME ($SHORT_GRAMMAR_NAME) ==\n[[Anchor($SHORT_GRAMMAR_NAME)]]\n''Published $pub_date''"
        table_footer=""
        # Data specific formatting
        if [ "$GRAMMAR_TYPE" ]; then
          GRAMMAR_TYPE="[#GrammarTypes $GRAMMAR_TYPE]"
        fi
        ;;
    latex)
        # LaTeX formatting does not include the extra anchoring row
        table_header='\\begin{tabular}{ll}'
        cs=" "
        cm="&"
        cmn=$cm
        ce="\\\\"
        table_footer='\\end{tabular}'
        ;;
    html)
        # HTML formatting 
        table_header="<table><caption>$GRAMMAR_NAME ($SHORT_GRAMMAR_NAME)</caption>"
        cs="<tr><th align='left'>"
        cm="</th><td>"
        cmn="</th><td align='right'>"
        ce="</td></tr>"
        table_footer='</table>'
	# URLS
	CONTACT_EMAIL="<a href='mailto:${CONTACT_EMAIL}?Subject=[${SHORT_GRAMMAR_NAME}]'>${CONTACT_EMAIL}</a>"
	WEBSITE="<a href='${WEBSITE}'>${WEBSITE}</a>"
	DEMO_WEBSITE="<a href='${DEMO_WEBSITE}'>${DEMO_WEBSITE}</a>"
	DOCUMENTATION_URL="<a href='${DOCUMENTATION_URL}'>${DOCUMENTATION_URL}</a>"
	ISSUE_TRACKER="<a href='${ISSUE_TRACKER}'>${ISSUE_TRACKER}</a>"
        ;;

esac

echo -e "$table_header"
echo "$cs maintainer                  $cm $MAINTAINER $ce"
echo "$cs contributors                $cm $CONTRIBUTORS $ce"
echo "$cs contact                     $cm $CONTACT_EMAIL $ce"
echo "$cs website                     $cm $WEBSITE $ce"
echo "$cs demo                        $cm $DEMO_WEBSITE $ce"
echo "$cs documentation               $cm $DOCUMENTATION_URL $ce"
echo "$cs issue tracker               $cm $ISSUE_TRACKER $ce"
echo "$cs version control             $cm $VCS $ce"
echo "$cs latest revision             $cm $REV_LATEST $ce"
echo "$cs latest release              $cm $LATEST_RELEASE $ce"
echo "$cs canonical citation          $cm $CITATION $ce"
echo "$cs license                     $cm $LICENSE $ce"
echo "$cs grammar type                $cm $GRAMMAR_TYPE $ce"
echo "$cs required external resources $cm $EXTERNAL_RESOURCES $ce"
echo "$cs associated resources        $cm $ASSOCIATED_RESOURCES $ce"
echo "$cs lexical items               $cmn $LEXICAL_ITEMS $ce"
echo "$cs lexical rules               $cmn $LEXICAL_RULES $ce"
echo "$cs grammar rules               $cmn $GRAMMAR_RULES $ce"
echo "$cs features                    $cmn $FEATURES $ce"
echo "$cs types (with glb)            $cmn $TYPES_WITH_GLB $ce"
echo -e "$table_footer"
