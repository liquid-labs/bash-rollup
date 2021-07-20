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
  echo "bash-rollup [--help|-h] [--source-only] [--no-chmod] <source index> <out file> [<search directory 1>...n]"
  echo
  echo 'Rollup behavior'
  echo '---------------'
  echo "Starting with the specified \"index\" bash file, bash-rollup will process 'source' and 'import' statements recursively, effectively inlining the target files as they are found. We use the terms 'include', 'included', etc. when referring to target files included via either 'source' or 'import' and 'sourced' and 'imported' when speaking specifically about one method or the other." | safe-fold
  echo
  echo "Non-static source statements containing a variable are left in place. E.g. 'source \"\${HOME}/script.sh\"' remains untouched and an informational note is emitted during processing. In instances where you can include/bundle the included script, this can be used as a workaround to force multiple inclusions of the same file until the 'always inline' flag is implemented (see below). Note that since 'import' is by definition a compile-time action, it is not possible to use a variable when specifying an import target." | safe-fold
  echo
  echo "Currently, bash-rollup will traverse symlinks by default. This will likely change before final release. (https://github.com/liquid-labs/bash-rollup/issues/7)" | safe-fold
  echo
  echo "'import' statements"
  echo '---------------'
  echo "In addition to standard bash 'source' statements, bash rollup supports an 'import' statement as well. 'import <name>' or 'import <name>.<type>' statements will search up to 3 levels deep of any explicit search paths given as optional trailing arguments to the bash-rollup invocation. This can be useful for including libraries from within the same project. './src' is implicitly included as a search directory unless the '--no-implicit-search' option is specified." | safe-fold
  echo
  echo "More standard the NPM 'devDependencies' of the current package where bash-rollup is being executed will be searched. This allows developers to include separate library packages (like @liquid-labs/bash-toolkit). If a file matching 'dist/*/<name>.<type>.sh' is found, it's included. Multiple matching files will generate an error." | safe-fold
  echo
  echo "The 'type' convention in import target file names is generally something like 'func' or 'inline', but is not currently standardized. Import statements may specify just the name like 'files' or the name and content type like 'files.funcs'. Future versions may specify recognized types and special handling. (https://github.com/liquid-labs/bash-rollup/issues/6)" | safe-fold
  echo
  echo 'Differences from runtime source'
  echo '---------------'
  echo "bash-rollup 'source' statements are generally functionally equivalent to runtime sourcing with three important caveats." | safe-fold
  echo
  echo "First, you must use 'source foo.sh' and cannot currently use the '. foo.sh' convention. Or rather, if you use '. foo.sh' then it will not be processed by bash-rollup, but you should not rely on this. Use the 'bash-rollup-ignore' flag instead. The release version will support '.' inclusion. (https://github.com/liquid-labs/bash-rollup/issues/5)" | safe-fold
  echo
  echo "Second, since the target file is being processed externally, and not directly by bash, it's possible to use include statements in places where you normally couldn't. Such as:" | safe-fold
  echo
  echo "SCRIPT=\$(cat <<'EOF'"
  echo 'source ./a-perl-script.pl # import also works!'
  echo 'EOF'
  echo ')'
  echo
  echo "The above has the effect of embedding the Perl file in the output script." | safe-fold
  echo
  # TODO: either implement special 'non-singleton' source support or remove the 'Future versions' statement.
  echo "Third, the included files are tracked and will not be included multiple times. This may break the expectation of some scripts, though there is a partial workaround discussed next. The final version will support a 'always inline' flag. (https://github.com/liquid-labs/bash-rollup/issues/4)" | safe-fold
  echo
  echo 'Source flags'
  echo '---------------'
  echo "'source' statements can be flagged by including a comment immediately after the source target which contains a single processing flag. E.g., 'source ./lib.sh # bash-rollup-no-recur'. Note, these flags don't really make sense with 'import' statements and therefore cannot be used with them." | safe-fold
  echo
  echo "* bash-rollup-ignore : will cause bash-rollup to skip processing the source and leave it as is."
  echo "* bash-rollup-no-recur : will cause the file to be included without itself being processed. This is useful for slupring in literal files that may contain 'source' and 'import' trigger statements." | safe-fold
  echo
  echo 'Post-rollup processing'
  echo '---------------'
  echo "After processing the file, the original index file starts with a shebang ('#!'), then it assumed to be an executable and 'chmod a+x' is applied to the output file unless the '--no-chmod' flag is present." | safe-fold
  echo
  echo 'Command options'
  echo '---------------'
  echo "* --no-chmod : suppresses the \"make output executable if shebang ('#!') present\" behavior." | safe-fold
  echo "* --no-implicit-search : keeps 'import' from looking in the current package's 'src' directory for target files." | safe-fold
  echo "* --no-recur : turns off recursion; only source and import statements in the index file are processed." | safe-fold
  echo "* --source-only : only 'source' statements are processed and import statements are passed through unprocessed into the final script." | safe-fold
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

TMP=$(${GNU_GETOPT} -o h --long help,source-only,no-chmod,no-implicit-search,no-recur -- "$@")
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
      --no-recur)
        NO_RECUR=true;;
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
    local NO_RECUR="${2:-}"
    [[ -n "${NO_RECUR:-}" ]] && NO_RECUR='--no-recur'
    (
      cd "${CONTEXT_DIR}"
      "${SCRIPT_PATH}" --no-implicit-search --source-only ${NO_RECUR} "$(basename "${FILE}")" /dev/stdout
    )
  }

  while read -r LINE; do
    if [[ -z "${NO_RECUR:-}" ]] && \
        ! [[ "${LINE}" =~ ^.*#\ *rollup-bash-ignore\ *$ ]] && \
        ! [[ "${LINE}" =~ ^.*#\ *bash-rollup-ignore\ *$ ]] && \
        [[ "${LINE}" =~ ^\ *source\ +([^#]+)(#\s*(bash-rollup-no-recur))?.*$ ]]; then
      # notice the positive match must be second so BASH_REMATCH is set as needed
      SOURCED_FILE=${BASH_REMATCH[1]} # no quotes! This Let's 'source foo #comment' work.
      NO_RECUR=${BASH_REMATCH[3]:-}
      echo "NO_RECUR from bash-rollup-204: ${NO_RECUR}" >&2
      process_source "${SOURCED_FILE}" "${NO_RECUR}"
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
source ./file-processor.pl
EOF
  )

  perl -e "$SCRIPT" "${MAIN_FILE}" "${OUT_FILE}" $SEARCH_DIRS
fi

# A little admin at the end.
if [[ "${OUT_FILE}" != '/dev/stdout' ]] && [[ "${OUT_FILE}" != '-' ]]; then
  # Make executable if indicated.
  if [[ -z "${NO_CHMOD:-}" ]] && [[ $(head -n 1 "${MAIN_FILE}") == "#!"* ]]; then
    chmod a+x "${OUT_FILE}"
  fi

  # And finally, test the resulting file is parsable.
  $(bash -n "${OUT_FILE}") || echoerrandexit "The rollup-script has syntax errors. See output above."
fi
