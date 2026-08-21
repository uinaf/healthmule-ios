SHELL := /bin/bash
.DEFAULT_GOAL := verify

.PHONY: project test-infra check-app-syntax test-core build test smoke harness run verify verify-full clean

VERIFY_FAST_TARGETS := test-infra check-app-syntax test-core
VERIFY_FAST_JOBS ?= 3

project:
	./scripts/with-xcode-lock.sh ./scripts/ios-project-task.sh project

test-infra:
	./scripts/test-infrastructure.sh

check-app-syntax:
	./scripts/check-swift-syntax.sh

test-core:
	./scripts/swift.sh test --parallel --disable-sandbox

build:
	./scripts/with-xcode-lock.sh ./scripts/ios-project-task.sh build

test:
	./scripts/with-xcode-lock.sh ./scripts/ios-project-task.sh test

smoke:
	./scripts/with-xcode-lock.sh ./scripts/ios-project-task.sh smoke

harness:
	./scripts/with-xcode-lock.sh ./scripts/ios-project-task.sh harness

run:
	./scripts/with-xcode-lock.sh ./scripts/ios-project-task.sh run

verify:
	$(MAKE) --no-print-directory --jobs=$(VERIFY_FAST_JOBS) $(VERIFY_FAST_TARGETS)

verify-full: verify
	$(MAKE) --no-print-directory test

clean:
	./scripts/swift.sh package clean
	./scripts/with-xcode-lock.sh ./scripts/ios-project-task.sh clean
