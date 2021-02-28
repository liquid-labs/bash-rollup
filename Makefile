.DELETE_ON_ERROR:

all: dist/bash-rollup.sh

clean:
	rm -rf dist .bu

dist/bash-rollup.sh: src/bash-rollup.sh src/file-processor.pl
	mkdir -p dist
	$< --source-only $< $@

.PHONY: all clean
