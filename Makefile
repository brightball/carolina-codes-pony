PONYC ?= ponyc
CORRAL ?= corral
SSL_DEFINE ?= openssl_3.0.x
BIN_DIR := build/carolina-codes-pony
TEST_DIR := build/pony-test

.PHONY: all test run fetch clean

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

clean:
	rm -rf build
