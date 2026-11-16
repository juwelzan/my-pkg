## Unreleased

- Part of the `omni_route` repository's pub workspace
  (`resolution: workspace`); one `flutter pub get` at the root resolves it.
- Added `repository`, `homepage` and `issue_tracker` to `pubspec.yaml`.
- Releases are tagged `omni_network_openapi-vX.Y.Z`.
- `environment` lowered to `sdk: ^3.5.0` (the code needs nothing newer;
  3.5 is the minimum for a pub workspace member).
- Dev dependency `test` relaxed to `^1.25.0` so it resolves together with
  the Flutter SDK's pinned `test_api`.

## 0.1.0-dev

- Step 13: OpenAPI 3.0/3.1 (JSON or YAML) → one Dart file with models
  (`fromJson`/`toJson`), enums and an `Endpoint` registry for OmniNetwork.
