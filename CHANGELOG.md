# Changelog

All notable user-visible changes to this project will be documented in this file.

## [Unreleased]

### Added

### Changed

### Fixed
- Fixed cron parsing to reject malformed tokens like trailing commas. (T-001)
- Fixed schedule calculation for impossible DOM/month combos and default re-parse behavior (e.g., seconds default to 0). (T-001)
- Fixed imMaxAsync keep-alive cleanup to avoid leaking async resources after callbacks. (T-001)
