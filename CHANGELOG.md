# Changelog

## Unreleased

### Added

- Isolated development identity, settings and history directory.
- Strict concurrency checks, formatting checks and MIT license.
- Frozen historical fixtures, interruption recovery tests and performance measurements.
- Clean application packaging, relocation smoke test and macOS 14 runtime CI.
- Manual signed-release workflow with notarization, checksums and symbol archives.

### Changed

- History saves are serialized and flushed before normal termination.
- History metadata is versioned; images and rich text are stored as separate payloads.
- Image recognition runs off the main actor; retention runs independently of capture.
- Application code moved into the `ClipletKit` library target; the package uses the Swift 6 language mode.
- A missing payload file no longer blocks the whole history; only the affected content is dropped.

### Fixed

- Prefer Plain Text no longer pastes recognized text in place of an image.
- Global shortcuts require Command, Option or Control; Shift alone is rejected.
- Automatic paste uses the V key of the current keyboard layout.
- A failed shortcut change reverts the stored shortcut to the one still active.
- Text and file entries with equal content hashes are no longer merged.

## Versioning

`VERSION` is the authoritative application version. Move the relevant Unreleased
entries into a dated version section before creating the matching `vMAJOR.MINOR.PATCH`
tag. No downloadable release is implied by the initial version value.
