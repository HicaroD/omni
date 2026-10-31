TELIA ?= telia
export T_VENDOR_PATH := $(CURDIR)/vendor

.PHONY: build run test test-release sanitize clean
build:
	mkdir -p bin
	$(TELIA) build "$(CURDIR)" -o bin/omni
run: build
	./bin/omni
test: build
	$(TELIA) build tests -o bin/test-rope
	./bin/test-rope
	python3 tests/terminal.py
test-release:
	mkdir -p bin
	$(TELIA) build "$(CURDIR)" -release -o bin/omni-release
	$(TELIA) build tests -release -o bin/test-rope-release
	./bin/test-rope-release
	OMNI_BINARY="$(CURDIR)/bin/omni-release" python3 tests/terminal.py
sanitize:
	python3 tests/sanitize.py
clean:
	rm -f bin/omni bin/test-rope
