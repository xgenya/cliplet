SWIFT_ENV = env CLANG_MODULE_CACHE_PATH=/tmp/cliplet-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/cliplet-swiftpm-cache
MACOS_SDK_PATH := $(shell xcrun --sdk macosx --show-sdk-path)
MACOS_SDK_VERSION := $(shell xcrun --sdk macosx --show-sdk-version)
# Record the SDK actually used, separately from the macOS 14 deployment target.
SWIFT_FLAGS = --arch arm64 --disable-sandbox --scratch-path .build --sdk "$(MACOS_SDK_PATH)" -Xswiftc -warnings-as-errors -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$(MACOS_SDK_VERSION)"

.PHONY: build test app dev-app run format lint check package-test performance release clean

build:
	$(SWIFT_ENV) swift build $(SWIFT_FLAGS)

test:
	$(SWIFT_ENV) swift test $(SWIFT_FLAGS) --skip PerformanceTests

app:
	./scripts/build-app.sh release

dev-app:
	./scripts/build-app.sh debug

run:
	$(SWIFT_ENV) swift run $(SWIFT_FLAGS) Cliplet

format:
	xcrun swift-format format --configuration .swift-format --in-place --recursive Package.swift Sources Tests

lint:
	xcrun swift-format lint --configuration .swift-format --strict --recursive Package.swift Sources Tests
	python3 scripts/check-repository.py

check: lint test

package-test: app
	./scripts/test-package.sh

performance:
	$(SWIFT_ENV) swift test $(SWIFT_FLAGS) -c release --filter PerformanceTests

release:
	./scripts/release.sh

clean:
	swift package clean
	rm -rf build
