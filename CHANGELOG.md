# Changelog

All notable user-visible changes to this project will be documented in this file.

## [Unreleased]

### Added
- Added Quartz-style DOM/DOW modifiers (`L`, `W`, `LW`, `#`, `?`). (T-005)
- Added cron macros (`@yearly`, `@monthly`, `@weekly`, `@daily`, `@hourly`, `@reboot`). (T-006)
- Added support for trailing `#` comments and flexible whitespace in cron strings. (T-010)
- Added cron dialect parsing for Standard 5-field and Quartz seconds-first formats. (T-008)

### Changed
- Changed the VCL help dialog to open help in an external browser instead of the legacy embedded control. (T-017)

### Fixed
- Fixed cron parsing to reject malformed tokens like trailing commas. (T-001)
- Fixed schedule calculation for impossible DOM/month combos and default re-parse behavior (e.g., seconds default to 0). (T-001)
- Fixed imMaxAsync keep-alive cleanup to avoid leaking async resources after callbacks. (T-001)
