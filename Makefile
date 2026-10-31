TELIA ?= telia
export T_VENDOR_PATH := $(CURDIR)/vendor

.PHONY: build run unit test test-release sanitize clean
build:
	mkdir -p bin
	$(TELIA) build . -o bin/omni
run: build
	./bin/omni
test: build
	$(TELIA) test --color=never
	python3 tests/terminal.py
unit:
	$(TELIA) test --color=never
test-release:
	mkdir -p bin
	$(TELIA) build . -release -o bin/omni-release
	$(TELIA) test --color=never
	OMNI_BINARY="$(CURDIR)/bin/omni-release" python3 tests/terminal.py
sanitize:
	python3 tests/sanitize.py
clean:
	rm -f bin/omni bin/omni-release bin/test-rope bin/test-rope-release
