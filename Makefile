V = 0
Q = $(if $(filter 1,$V),,@)

M = $(shell if [ "$$(tput colors 2> /dev/null || echo 0)" -ge 8 ]; then printf "\033[34;1m▶\033[0m"; else printf "▶"; fi)

# Prefer the checkout's venv, fall back to whatever is on PATH so CI
# (which pip-installs into the job's interpreter) works unchanged.
PY ?= $(shell [ -x .venv/bin/python ] && echo .venv/bin/python || echo python3)

ROM = build/ff4.sfc
IPS = build/ff4.ips
# -o binds looser than -not, so the extension test needs its own group
# or .s files under .venv/ come along.
SOURCES = $(shell find . -path ./.venv -prune -o \( -name '*.s' -o -name '*.i' \) -print)

.SUFFIXES:
.PHONY: all
all: | build tests  ## Build the patch and run the tests

.PHONY: build
build: $(IPS)  ## Assemble the IPS patch

# The base ROM is deliberately not a prerequisite: as a rule it would be
# something `make -B` tries to remake, and it is an input we can only ask
# the user to provide. CI decrypts ff4.sfc.gz.gpg into place.
$(IPS): $(SOURCES)
	$(Q) test -s $(ROM) || { \
		echo "$(ROM) missing. Decrypt it with:"; \
		echo "  gpg --decrypt ff4.sfc.gz.gpg | gunzip > $(ROM)"; \
		exit 1; }
	$(info $(M) Building patch...)
	$(Q) $(PY) ./build.py
	$(Q) test -s $(IPS)

.PHONY: tests
tests: $(IPS)  ## Run the full suite against a freshly built patch
	$(info $(M) Running tests...)
	$(Q) $(PY) -m pytest

.PHONY: test
test: tests  ## Alias for `tests`

.PHONY: check
check:  ## Verify .s/.i formatting and run the a816 fluff lints
	$(info $(M) Checking sources...)
	$(Q) a816 format --check $(SOURCES)
	$(Q) a816 check $(SOURCES)

.PHONY: format
format:  ## Rewrite .s/.i sources in a816 canonical form
	$(info $(M) Formatting sources...)
	$(Q) a816 format $(SOURCES)

.PHONY: clean
clean:  ## Remove build products, keeping the base ROM
	$(info $(M) cleaning ...)
	$(Q) rm -f $(IPS) $(IPS).adbg build/ff4-patched.sfc a.out a.out.adbg
	$(Q) rm -rf build/obj __pycache__ .pytest_cache

.PHONY: help
help: ## Display help
	@grep -hE '^[ a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-17s\033[0m %s\n", $$1, $$2}'
