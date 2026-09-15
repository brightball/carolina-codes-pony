PONYC ?= ponyc
CORRAL ?= corral
SSL_DEFINE ?= openssl_3.0.x
BIN_DIR := build/carolina-codes-pony
TEST_DIR := build/pony-test
# ponyup ships ponyc/corral/pony-lint; mise shims cover gitleaks/osv-scanner;
# uv tool install puts semgrep in ~/.local/bin.
export PATH := $(HOME)/.local/share/ponyup/bin:$(HOME)/.local/bin:$(HOME)/.local/share/mise/shims:$(PATH)
APP_PONY := carolina test main.pony
SEMGREP ?= semgrep
OSV_SCANNER ?= osv-scanner
GITLEAKS ?= gitleaks
PONY_LINT ?= pony-lint

.PHONY: all test run fetch clean sast audit gitleaks lint pony-lint check hooks

all: $(BIN_DIR)/pony

fetch:
	$(CORRAL) fetch

$(BIN_DIR)/pony: fetch
	mkdir -p $(BIN_DIR)
	$(CORRAL) run -- $(PONYC) --path=. -D$(SSL_DEFINE) --bin-name pony -o $(BIN_DIR) .

$(TEST_DIR)/test: fetch
	mkdir -p $(TEST_DIR)
	$(CORRAL) run -- $(PONYC) --debug --path=. -D$(SSL_DEFINE) -o $(TEST_DIR) test

test: $(TEST_DIR)/test
	$(TEST_DIR)/test

run: $(BIN_DIR)/pony
	$(BIN_DIR)/pony

# Generic + p/security-audit Semgrep. Pony has no native SAST.
sast:
	$(SEMGREP) scan --error --metrics=off --jobs 1 \
		--exclude=_corral --exclude=_repos --exclude=build --exclude=.cursor \
		--config=p/security-audit --config=.semgrep.yml .

# corral lock.json is not a native OSV lockfile; generate a commit scan first.
audit: lock.json scripts/corral_to_osv.py
	python3 scripts/corral_to_osv.py
	$(OSV_SCANNER) scan source --lockfile osv-scanner:osv-scanner-custom.json --all-packages

gitleaks:
	$(GITLEAKS) detect --source . --verbose

lint: pony-lint

pony-lint: fetch
	$(CORRAL) run -- $(PONY_LINT) $(APP_PONY)

# Local convenience only. Gitea runs each target as its own job.
check: test sast audit gitleaks lint

hooks:
	pre-commit install
	git config core.hooksPath .githooks

clean:
	rm -rf build osv-scanner-custom.json
