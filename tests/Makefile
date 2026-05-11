# anvil/tests/Makefile — convenience targets for the smoke-test suite.
#
# Run:
#   make smoke           # run all smoke tests
#   make smoke FILE=...  # run a single bats file
#   make list            # list discovered bats files

SHELL := /usr/bin/env bash

TESTS_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
SMOKE_DIR := $(TESTS_DIR)smoke

BATS_FILES := $(sort $(wildcard $(SMOKE_DIR)/*.bats))

.PHONY: smoke list help

help:
	@echo "anvil test targets:"
	@echo "  make smoke           # run the full smoke suite"
	@echo "  make smoke FILE=x    # run a single bats file (path relative to smoke/)"
	@echo "  make list            # list discovered bats files"
	@echo ""
	@echo "Requirements:"
	@echo "  - bats-core (brew install bats-core / apt install bats)"
	@echo "  - jq"
	@echo ""

list:
	@for f in $(BATS_FILES); do echo "  $$f"; done

smoke:
ifeq ($(strip $(FILE)),)
	@if ! command -v bats >/dev/null 2>&1; then \
		echo "bats not installed — brew install bats-core (or apt install bats)" >&2; \
		exit 1; \
	fi
	bats $(BATS_FILES)
else
	bats $(SMOKE_DIR)/$(FILE)
endif
