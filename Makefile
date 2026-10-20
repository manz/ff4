V = 0
Q = $(if $(filter 1,$V),,@)

M = $(shell if [ "$$(tput colors 2> /dev/null || echo 0)" -ge 8 ]; then printf "\033[34;1m▶\033[0m"; else printf "▶"; fi)

# Prefer the checkout's venv (`uv sync` creates it), fall back to whatever
# is on PATH.
PY ?= $(shell [ -x .venv/bin/python ] && echo .venv/bin/python || echo python3)
A816 ?= $(shell [ -x .venv/bin/a816 ] && echo .venv/bin/a816 || echo a816)

ROM = build/ff4.sfc
IPS = build/ff4.ips
RELEASE_IPS = build/release/ff4.ips
EN_IPS = build/en/ff4.ips
EN_RELEASE_IPS = build/en/release/ff4.ips
BPS = build/release/ff4.bps build/en/release/ff4.bps
FLIPS ?= flips
# BUILD_DATE (the DEBUG stamp) from the last commit, not the clock: two builds of one commit are byte-identical.
export SOURCE_DATE_EPOCH ?= $(shell git log -1 --format=%ct 2>/dev/null || echo 0)
# Prune hidden directories: they never hold our sources, and .venv matches
# too, so the .s files a816 ships stay out. -o binds looser than -not, so
# the extension test needs its own group or pruned paths come along.
SOURCES = $(shell find . -path './.*' -prune -o \( -name '*.s' -o -name '*.i' \) -print)
# What build.py turns into assets: text, tables, fonts, the generators.
ASSET_INPUTS = build.py a816.toml katsuji.toml $(shell find text fonts utils -type f -not -name '*.pyc')

.SUFFIXES:
.PHONY: all
all: | build tests  ## Build the patch and run the tests

.PHONY: build
build: $(IPS)  ## Assemble the IPS patch

# The base ROM is deliberately not a prerequisite: as a rule it would be
# something `make -B` tries to remake, and it is an input we can only ask
# the user to provide. CI decrypts ff4.sfc.gz.gpg into place with a
# secret passphrase.
$(IPS): $(SOURCES) $(ASSET_INPUTS)
	$(Q) test -s $(ROM) || { \
		echo "$(ROM) missing. Place an unheadered Final Fantasy IV (J) ROM there."; \
		exit 1; }
	$(info $(M) Building patch...)
	$(Q) $(PY) ./build.py --dev
	$(Q) test -s $(IPS)

.PHONY: release
release: $(RELEASE_IPS)  ## Assemble the release patch: DEBUG=0, no build stamp

$(RELEASE_IPS): $(SOURCES) $(ASSET_INPUTS)
	$(Q) test -s $(ROM) || { \
		echo "$(ROM) missing. Place an unheadered Final Fantasy IV (J) ROM there."; \
		exit 1; }
	$(info $(M) Building release patch...)
	$(Q) $(PY) ./build.py
	$(Q) test -s $(RELEASE_IPS)

.PHONY: en
en: $(EN_IPS)  ## Assemble the English patch (FF4_LANG=en). It regenerates build/gen: rerun `make -B` before the tests

$(EN_IPS): $(SOURCES) $(ASSET_INPUTS)
	$(Q) test -s $(ROM) || { \
		echo "$(ROM) missing. Place an unheadered Final Fantasy IV (J) ROM there."; \
		exit 1; }
	$(info $(M) Building English patch...)
	$(Q) FF4_LANG=en $(PY) ./build.py --dev
	$(Q) test -s $(EN_IPS)

$(EN_RELEASE_IPS): $(SOURCES) $(ASSET_INPUTS)
	$(Q) test -s $(ROM) || { \
		echo "$(ROM) missing. Place an unheadered Final Fantasy IV (J) ROM there."; \
		exit 1; }
	$(info $(M) Building English release patch...)
	$(Q) FF4_LANG=en $(PY) ./build.py
	$(Q) test -s $(EN_RELEASE_IPS)

.PHONY: bps
bps: $(BPS)  ## BPS patches of both release builds, next to their IPS (needs flips: github.com/Alcaro/Flips)

# A BPS is a diff of two ROMs: the IPS applied to the base ROM, then diffed against it.
%/ff4.bps: %/ff4.ips
	$(info $(M) Creating $@...)
	$(Q) $(FLIPS) --apply $< $(ROM) $*/ff4-bps.sfc > /dev/null
	$(Q) $(FLIPS) --create --bps-delta $(ROM) $*/ff4-bps.sfc $@ > /dev/null
	$(Q) rm $*/ff4-bps.sfc

.PHONY: tests
tests: $(IPS)  ## Run the full suite against a freshly built patch, one worker per core
	$(info $(M) Running tests...)
	$(Q) $(PY) -m pytest -n auto

.PHONY: test
test: tests  ## Alias for `tests`

.PHONY: screenshots
screenshots: $(IPS)  ## Regenerate the README screenshots from the savestates
	$(info $(M) Capturing screenshots...)
	$(Q) $(PY) utils/readme_shots.py

.PHONY: check
check:  ## Verify .s/.i formatting and run the a816 fluff lints
	$(info $(M) Checking sources...)
	$(Q) $(A816) format --check $(SOURCES)
	$(Q) $(A816) check $(SOURCES)

.PHONY: format
format:  ## Rewrite .s/.i sources in a816 canonical form
	$(info $(M) Formatting sources...)
	$(Q) $(A816) format $(SOURCES)

.PHONY: clean
clean:  ## Remove build products, keeping the base ROM
	$(info $(M) cleaning ...)
	$(Q) rm -f $(IPS) $(IPS).adbg build/ff4-patched.sfc a.out a.out.adbg
	$(Q) rm -rf build/obj __pycache__ .pytest_cache

.PHONY: help
help: ## Display help
	@grep -hE '^[ a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-17s\033[0m %s\n", $$1, $$2}'
