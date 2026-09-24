SWIFT = ./scripts/swift.sh

.PHONY: build test app dev-app run format lint check package-test performance release clean

build:
	$(SWIFT) build

test:
	$(SWIFT) test --skip PerformanceTests

app:
	./scripts/build-app.sh release

dev-app:
	./scripts/build-app.sh debug

run:
	$(SWIFT) run Cliplet

format:
	xcrun swift-format format --configuration .swift-format --in-place --recursive Package.swift Sources Tests

lint:
	xcrun swift-format lint --configuration .swift-format --strict --recursive Package.swift Sources Tests
	python3 scripts/check-repository.py

check: lint test

package-test: app
	./scripts/test-package.sh

performance:
	$(SWIFT) test -c release --filter PerformanceTests

release:
	./scripts/release.sh

clean:
	swift package clean
	rm -rf build
