SRC_FILES:=$(shell find src -type f -not -name bash-rollup.sh) # bash-rollup.sh is explicitly named

.DELETE_ON_ERROR:

all: dist/bash-rollup.sh

clean:
	rm -rf dist .bu

.PHONY: all clean

dist/bash-rollup.sh: src/bash-rollup.sh $(SRC_FILES)
	mkdir -p dist
	cd $(dir $<) && ./$(notdir $<) --source-only $(notdir $<) ../$@
