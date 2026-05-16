# Changelog

## 0.1.1

- Test coverage parity bump: adds a regression test ensuring a non-404 4xx
  response from the CDN propagates immediately instead of being retried.
  No SDK behavior change.

## 0.1.0

- Initial release. Feature parity with the Go SDK: `lookup`, `lookupGroup`,
  `lookupAll`, `preload`, `getMeta`, `refresh`, and `isValidZipcode`. L1
  in-memory LRU cache and pluggable L2 persistent cache with data-version
  invalidation.
