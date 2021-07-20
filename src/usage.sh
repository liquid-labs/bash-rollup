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
