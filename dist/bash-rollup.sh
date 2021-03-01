#!/usr/bin/env bash

# DEVELOPER NOTES -------------------------


# Possible TODO? This script was originally setup to support a two-step process whereby standard bash libraies could be
# imported on the second run. I.e., in a first '--source-only' pass, the perl script is embedded. Then a second pass is
# applied to that file to import the libraries.

# Actually, for this to work, we would add an '--obliterate-imports' option. Then the script could do something like:
#
#    import foo
#    if [[ -z "FOO" ]]; then
#       FOO='a shim value'
#    fi
#
# Of course, with the more common case be checking for and defining a function, but you get the idea. That way we would
# use shim functions while building ourselves to "get the job done", but then the dist script would import the fully
# tested and presumably more reliable and correct standard functions.

# This idea was dropped for the sake of simplicity, but might bo something we want to conisder later.

# END DEVELOPR NOTES ---------------------

# bash strict settings
set -o errexit # exit on errors
set -o nounset # exit on use of uninitialized variable
set -o pipefail

# Folds output if the 'fold' executable is available. Otherwise, just passes it along. Ex:
#
#     echo "This is an example!" | safe-fold
safe-fold() {
if which fold > /dev/null; then
fold -sw 82
else
cat -
fi
}

# TODO?: Another trick we could do is document this as an MD file that gets processed during sourcing. Something like:
#
#    import-doc XXX echo
usage() {
echo "Usage:"
echo
echo "bash-rollup [--help|-h] [--source-only] [--no-chmod] <source 'index'> <out file> [<search directory 1>...n]"
echo
echo "Starting with the source index bash file, will process 'source' and 'import' statements recursively replacing them with the content of the indicated file, combining the static source and import files and printing the result to stdin." | safe-fold
echo
echo "Static 'source' statements are replaced with the contents of the sourced file. This ends up being functionally the same for the most part with two important notes. First, since the target file is being processed externally, and not directly by bash, it's possible to use source statements in places where you normally couldn't. Such as:" | safe-fold
echo
echo -e "SCRIPT=\$(cat <<'EOF'
source ./file-processor.pl 
EOF
)"
echo
# TODO: either implement special 'non-singleton' source support or remove the 'Future versions' statement.
echo "Second, the sourced files are tracked and will not be included multiple times. This may break the expectation of some scripts, though there is a partial workaround discussed next. Future versions may support special syntax or additional options in order to better support this case." | safe-fold
echo
echo "Non-static sources statements containing a variable are left in place. E.g. 'source \"\${HOME}/script.sh\"' remains untouched. Assuming you can distribute the included file" | safe-fold
echo
echo "'import <name>' statements will examine the 'devDependencies' of the current package and search them for a files with a path matching '*/src/*/<name>.func.sh'. The processed file contents replace the import statement.". | safe-fold
echo
echo "The '--source-only' option is an alternate mode in which only 'source' statement are processed and import statements are treated as any other line." | safe-fold
echo
echo "After processing the file, the original index file starts with a shebang ('#!'), then it assumed to be an executable and 'chmod a+x' is applied to the output file unless the '--no-chmod' flag is present." | safe-fold
echo
echo "The target library files searched by import must match: '<name>.<content type>.sh'. The 'content type' is generally something like 'func' or 'script', but is not currently standard. Import statements may specify just the name like 'files' or the name and content type like 'files.funcs'."
echo
echo "The files must be in either the expclicit search directories or the 'dist' folder of included pacages no more than 3 folders deeps. Sym-linked directories and files will be considered. This behavior is somewhat arbitrary, but hardcoded for simplicity."
}

# Shim colors.
RED=$(tput setaf 1)
RESET=$(tput sgr0)

# Default options
SOURCE_ONLY=

# Spits out red text on stderr in interactive mode.
echoerrandexit() {
if [[ -n "${PS1:-}" ]]; then
echo -e "${RED}${*}${RESET}" | safe-fold >&2
else
echo "${*}" | safe-fold >&2
fi
exit ${2:-}
}

# Can't use the options lib, so we do some traditional getopt processing.
# If getopt isn't availbale, we'll continue so long as there are no options in the parameters
ensure-no-options() {
for ARG in "${@}"; do
if [[ "${ARG}" == '-'* ]]; then
echoerrandexit "GNU's 'getopt' does not appear to be available on your system. Cannot proceed."
exit 20
fi
done
}
if [[ $(uname) == 'Darwin' ]]; then
GNU_GETOPT="$(brew --prefix gnu-getopt)/bin/getopt" || ensure-no-options
else
GNU_GETOPT="$(which getopt)" || ensure-no-otpions
fi

TMP=$(${GNU_GETOPT} -o h --long help,source-only,no-chmod,no-implicit-search -- "$@")
[ $? -eq 0 ] || {
usage
echo -e "${RED}Bad options. See usage above.${RESET}"
exit 1
}
eval set -- "${TMP}"
while true; do
case "$1" in
--help|-h)
usage
exit 0;;
--source-only)
SOURCE_ONLY=true;;
--no-chmod)
NO_CHMOD=true;;
--no-implicit-search)
NO_IMPLICIT_SEARCH=true;;
--)
shift; break;;
esac
shift
done

(( $# == 2 )) || { usage; echoerrandexit "Invalid arguments: '${@:-}'. See usage above."; }

abspath() {
local FILE="${1}"
local ABS_DIR
ABS_DIR="$(absdir "${FILE}")"
if [[ "${ABS_DIR}" == "${FILE}" ]]; then
echo "${FILE}"
else
echo "${ABS_DIR}/$(basename $FILE)"
fi
}

absdir() {
local FILE="${1}"
local DIR_NAME
DIR_NAME="$(dirname "${FILE}")"
# If we get something other than a file name, like '-', then 'DIR_NAME' will be '.'. If that happens and the 'FILE'
# is not actually a file name, we pass along the original string.
if [[ "${DIR_NAME}" == '.' ]] && ! [[ -e "${FILE}" ]]; then
echo "${FILE}"
else
echo "$( cd "${DIR_NAME}" >/dev/null 2>&1 ; pwd -P )"
fi
}

MAIN_FILE="${1:-}"; shift # arg 1
{ [[ -f "${MAIN_FILE}" ]] || [[ -L "${MAIN_FILE}" ]]; } \
|| { usage; echoerrandexit "The input file '${MAIN_FILE}' does not exist."; }
CONTEXT_DIR="$( absdir "${MAIN_FILE}" )"
MAIN_FILE="$( abspath "${MAIN_FILE}" )"

OUT_FILE="${1:-}"; shift # arg2
OUT_FILE="$( abspath "${OUT_FILE}")"

SCRIPT_PATH="$( abspath "${0}" )"

if [[ -z "${SOURCE_ONLY}" ]]; then
SEARCH_DIRS="$@"
[[ -n "${NO_IMPLICIT_SEARCH:-}" ]] || {
# the assumption is that our initial working dir is always a package, so it gets added
SEARCH_DIRS="${SEARCH_DIRS:-} ${PWD}/src" # had '.' initially, but I think PWD gives same results and clearer?
# Now add all our dev dependencies, resolving the NPM packages to actual directories.
while read -r PKG_NAME; do
CANDIDATE="$(npm explore "${PKG_NAME}" -- pwd)/dist"
if [[ -e  "${CANDIDATE}" ]]; then
# TODO: this is probably the best argument for a 2-pass approach as discussed above
SEARCH_DIRS="${SEARCH_DIRS} ${CANDIDATE}"
fi
done < <(cat package.json | jq -r '.devDependencies | keys | .[]')
}
fi

if [[ -n "${SOURCE_ONLY}" ]]; then
process_source() {
local FILE="${1}"
(
cd "${CONTEXT_DIR}"
"${SCRIPT_PATH}" --no-implicit-search --source-only "$(basename "${FILE}")" /dev/stdout
)
}

while read -r LINE; do
if ! [[ "${LINE}" =~ ^.*#\ *rollup-bash-ignore\ *$ ]] && [[ "${LINE}" =~ ^\ *source\ +([^#]+).*$ ]]; then
# notice the positive match must be second so BASH_REMATCH is set as needed
SOURCED_FILE=${BASH_REMATCH[1]} # no quotes! This Let's 'source foo #comment' work.
process_source "${SOURCED_FILE}"
else
echo "${LINE%# rollup-bash-ignore}"
fi
done < <(cat "${MAIN_FILE}") > "${OUT_FILE}" # Note we replace existing file if any.
else # process for reals
if ! which -s perl; then
echoerrandexit "Perl is required."
exit 10
fi

SCRIPT=$(cat <<'EOF'
use strict;
use warnings;
use Term::ANSIColor;
use File::Spec;

# TODO: track file as they are included <- done?

my $main_file=shift;
my $output_file=shift;
my @search_dirs=@ARGV;

my $find_search=join(' ', map("'$_'", @search_dirs));

my $output;
if ("$output_file" eq "-") {
$output = *STDOUT;
}
else {
open($output, '>:encoding(UTF-8)', $output_file)
or die "Could not open file '$output_file'";
}

my $sourced_files = {};

sub printErr {
my $msg = shift;

print STDERR color('red');
print STDERR "$msg\n";
print STDERR color('reset');
}

sub process_file {
my $input_file = shift;
my $input_abs = $input_file =~ m|^/| && $input_file || File::Spec->rel2abs($input_file);
my $source_base=($input_file =~ m|^(.*)/| ? $1 : ""); # that's 'dirname'
if ($sourced_files->{$input_abs}) {
# TODO: if 'verbose'
# print "Dropping additional inclusion of '$input_file'.\n";
return;
}
$sourced_files->{$input_abs} = 1;

open(my $input, '<:encoding(UTF-8)', $input_file)
or die "Could not open file '$input_file'";

while (<$input>) {
# Tried to do the 'comment' check as a negative lookahead, but was tricky.
if ($_ !~ /#.*import\s+/ && /(^|;|do +|then +)\s*import\s+([^;\s]+)/) {
my $pattern=$2;
# sharpen the match to a standard '<name>.*=<content type>.sh' if not specified.
$pattern !~ /\.$/ and $pattern .= '.';
# Note, we *do* follow links and limit depth to 4.
# TODO: in future, these can be turned into options if use case presents
my $source_name=`find -L $find_search -maxdepth 4 -path "*/$pattern*.sh" -not -name '*.test.*' -not -name '*.seqtest.*'`;
my $source_count = split(/\n/, $source_name);
if ($source_count > 1) {
printErr "Ambiguous results trying to import '$pattern' in file $input_file".' line '."$.\nLooking in: $find_search\nGot:\n$source_name\n";
die 10;
}
elsif ($source_count == 0) {
printErr "No source found trying to import '$pattern' in file $input_file".' line '."$.\nLooking in: $find_search";
die 10;
}
else {
chomp($source_name);
process_file($source_name);
}
}
elsif ($_ !~ /#.*source\s+/ && m:(^|;|do +|then +)\s*source\s+((\./)?([^;\s]+)):) {
my $next_file="$source_base/$4";
my $source_spec="$2";
if ($next_file =~ /\$/) {
print "Leaving dynamic source: '$source_spec' in $input_file".'@'."$.\n";
print $output $_;
}
elsif (-f "$next_file") {
process_file($next_file);
}
else {
# TODO: support an 'ignore' directive like we do in the 'source-only' mode (see bash script)
printErr "No source found trying to source '$source_spec' in file $input_file".'@'."$.";
die 10
}
}
else {
print $output $_;
}
}
}

process_file($main_file);
EOF
)

perl -e "$SCRIPT" "${MAIN_FILE}" "${OUT_FILE}" $SEARCH_DIRS
fi

# A little admin at the end.
if [[ "${OUT_FILE}" != '/dev/stdout' ]] && [[ "${OUT_FILE}" != '-' ]]; then
if [[ -z "${NO_CHMOD:-}" ]] && [[ $(head -n 1 "${MAIN_FILE}") == "#!"* ]]; then
chmod a+x "${OUT_FILE}"
fi

$(bash -n "${OUT_FILE}") || echoerrandexit "The rollup-script has syntax errors. See output above."
fi
