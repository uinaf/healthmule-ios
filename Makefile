SHELL := /bin/bash
.DEFAULT_GOAL := verify

.PHONY: project test-infra check-app-syntax test-core build test smoke harness run verify verify-full clean

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

verify: test-infra check-app-syntax test-core

verify-full: test-infra check-app-syntax test-core test

clean:
	./scripts/swift.sh package clean
	./scripts/with-xcode-lock.sh ./scripts/ios-project-task.sh clean
