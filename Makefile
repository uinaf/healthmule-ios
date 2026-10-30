SHELL := /bin/bash
.DEFAULT_GOAL := verify

.PHONY: project check-app-syntax check-app-dependencies test-core test-core-cached build test smoke harness run verify verify-cached verify-full clean

VERIFY_FAST_TARGETS := check-app-syntax check-app-dependencies test-core
VERIFY_FAST_JOBS ?= 2

project:
	./scripts/with-xcode-lock.sh ./scripts/ios-project-task.sh project

check-app-syntax:
	./scripts/check-swift-syntax.sh

check-app-dependencies:
	./scripts/check-app-dependencies.sh

test-core:
	./scripts/swift.sh test --parallel --disable-sandbox

test-core-cached:
	./scripts/swift.sh test --skip-build --parallel --disable-sandbox

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

verify-cached:
	$(MAKE) --no-print-directory --jobs=$(VERIFY_FAST_JOBS) check-app-syntax check-app-dependencies test-core-cached

verify-full: verify
	$(MAKE) --no-print-directory test

clean:
	./scripts/swift.sh package clean
	./scripts/with-xcode-lock.sh ./scripts/ios-project-task.sh clean
