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

source ./usage.sh

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
  if [[ -z "$(which perl)" ]]; then
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
