# AGENTS.md

Guidance for AI agents working in this repository.

## What this is

`mingchao_echo_scorer`（鸣潮声骸评分）is a **fully offline** Flutter app for
Android + Windows that scores 声骸 (echoes) for the game 鸣潮 (Wuthering Waves).
It is a real, layered application — no longer the `flutter create` counter
template. The counter `MyApp` is gone; `lib/main.dart` now wires up providers and
`lib/app.dart` holds `EchoScorerApp`.

Hard product constraints (do not violate without the user asking):
- **完全离线**：no network, no login, no telemetry. There is **no `http`/network
  dependency anywhere** and the Android manifest declares **no `INTERNET`
  permission**. The only external hand-off is `url_launcher` opening the GitHub
  repo in the system browser; the manifest adds an `https` `<queries>` intent
  purely for package visibility. Keep it that way.
- **本地存储**：all data lives in the app storage directory as JSON.
- **至多 5 条副词条**：an echo may have at most 5 non-zero substat tiers. If more
  than 5 are filled, the app must **not** output a score for that echo and must
  show a prompt instead (see `OutputPanel` / `EchoCard` over-filled branches).
- **Word 式脏检查**：closing/switching with no real change must not prompt. Dirty
  state is a *semantic* comparison against the last-persisted content, not a
  "was edited" flag.

## Architecture

Layered, dependency flows downward only (`ui → state → domain/data → core`):

- `lib/core/` — cross-cutting: `constants.dart` (`AppConstants`), `util/format.dart`
  (`Format` display strings), `util/file_names.dart`, `theme/` (`AppTheme`,
  `AppPalette`), `io/transfer.dart` (JSON pick/save via `file_picker`).
- `lib/data/` — `catalog/` (built-in `SubstatType`, `tier_group` probability
  tables — **must stay built-in, no download**), `models/` (`ScoreFile`,
  `EchoEntry`, `Coefficients`, `CoefficientProfile`, `Rating`, `json_format`),
  `repositories/` (`StorageService`, `ScoreRepository`, `ProfileRepository`,
  `SettingsRepository`). Each score file is `<scores>/<name>/score.json`.
- `lib/domain/` — pure calculators, no Flutter/IO: `score_calculator.dart`,
  `expected_max_calculator.dart`, `probability_calculator.dart`.
- `lib/state/` — `ChangeNotifier` controllers (`WorkspaceController`,
  `ProfileController`, `SettingsController`) plus a plain `AppScope` container.
  Provided via `provider` in `main.dart`. No router: the shell switches views with
  the `ShellView` enum; modal pages (echo detail, profile editor) use
  `Navigator.push`.
- `lib/ui/` — `shell/` (`AppShell`, `NavRail`, `FilePanel`, `TopToolbar`),
  `overview/`, `detail/`, `profiles/`, `settings/`, `actions/` (`FileActions`,
  `ProfileActions` — glue between widgets and controllers), `widgets/`
  (`Dialogs`, `RatingChip`, `PageHeader`).

Key invariants:
- **Derived data is never persisted.** Score, rating, expected-max, and
  probability are always recomputed from `tiers + coefficients`.
- **Coefficients are snapshotted** into each `ScoreFile` when a profile is
  applied, so later profile edits don't silently rescore saved files.
- Accumulate at **full precision, round once** to 2 decimals for display
  (`ScoreCalculator.roundTo2`).
- `EchoEntry.sameContentAs` / `ScoreFile.sameContentAs` drive dirty tracking;
  keep them in sync when adding fields. NaN target scores compare equal.

## Verified commands

Run from the repository root (`E:\mingchao\mingchao_echo_scorer`):

```bash
flutter pub get                 # resolve dependencies
flutter analyze                 # static analysis + lints (keep it clean)
flutter test                    # all tests (unit + widget)
flutter test test/widget_test.dart                  # widget tests only
flutter test --plain-name "详情页实时输出当前评分与预期最高分"   # single case
dart format lib test            # formatting (run before committing)
flutter run -d windows          # desktop run (fastest local iteration)
flutter build windows --debug   # verify Windows compiles
flutter run -d android          # device/emulator run
flutter build apk --debug       # verify Android compiles
```

`flutter analyze` ~8s and `flutter test` ~11s on a warm cache; run both before
reporting work complete.

## Toolchain

- Flutter 3.47.5 stable / Dart 3.13.4, installed at `E:/flutter/bin` (on PATH).
  `flutter doctor` is clean: Android SDK 36 and Visual Studio 2026 (Windows
  desktop) are both available, so both targets can be built locally.
- SDK constraint in `pubspec.yaml` is `sdk: ^3.13.4`. Do not lower it.
- Pub and asset downloads use Chinese mirrors (`pub.flutter-io.cn`,
  `storage.flutter-io.cn`, Tsinghua git mirror for the SDK). The "assets will be
  downloaded from storage.flutter-io.cn" notice on every command is expected —
  not an error, and not something to "fix" by changing mirror env vars.

## Dependencies

Runtime deps beyond the Flutter SDK (see `pubspec.yaml`): `provider` (state),
`path` + `path_provider` + `shared_preferences` (storage/settings), `file_picker`
(import/export JSON, choose folders), `url_launcher` (GitHub link),
`window_manager` (Windows close interception), `flutter_localizations` + `intl`
(zh_CN). Adding a dependency that implies network access contradicts the offline
constraint — don't.

## Platforms

Only `android/` and `windows/` platform folders exist. There is no `ios/`,
`web/`, `macos/`, or `linux/` support. Don't add platform directories, and don't
write platform-specific code for platforms that aren't present, unless explicitly
asked.

Android specifics (`android/app/build.gradle.kts`, `android/settings.gradle.kts`):
- `applicationId` / `namespace`: `io.github.hmsdido.mingchao_echo_scorer`
- `android:label` is `鸣潮声骸评分` (in `AndroidManifest.xml`).
- Gradle 9.3.1, AGP 9.1.0, Kotlin 2.4.0, Java/Kotlin target 17
- `minSdk`/`targetSdk`/`compileSdk` come from the Flutter Gradle plugin defaults
- Release builds are still signed with **debug** keys (explicit `TODO` in
  `build.gradle.kts`) — signing must be configured before any real release.
- App version lives in `pubspec.yaml` (`version: 1.0.0+1`) and is mirrored by
  `AppConstants.version`; keep the two in sync.

Windows specifics: `main.dart` calls `windowManager.setPreventClose(true)` so
`AppShell.onWindowClose` can run leave-guards and prompt before exit. This path
is Windows-only (`Platform.isWindows`); on Android the guard is disabled.

## Code style and linting

- `analysis_options.yaml` includes `package:flutter_lints/flutter.yaml`
  (flutter_lints ^6.0.0) with **no** extra rules enabled and none disabled. It
  excludes `build/**`, `android/**`, `windows/**`, so native code is not linted.
  `flutter analyze` must stay at "No issues found!".
- The code uses Dart dot-shorthand (`.fromSeed(...)`, `.center`,
  `.headlineMedium`) and null-aware elements (`?trailing`). Valid under Dart 3.13
  — match the existing style instead of "correcting" it.
- `uses-material-design: true`; Material + `cupertino_icons` only. No custom
  fonts or asset bundles are declared. The catalog data is compiled-in Dart, not
  an asset — adding assets requires extending the `flutter:` section of
  `pubspec.yaml`.

## Testing notes

- `test/` has pure-Dart unit tests (`score_calculator_test`, `rating_test`,
  `expected_max_test`, `probability_calculator_test`, `catalog_test`,
  `file_names_test`, `repositories/*_test`) plus `test/widget_test.dart` (13
  end-to-end widget tests over the real UI). ~105 tests total.
- **Real `dart:io` futures hang if awaited directly in a `testWidgets` body** —
  the fake-async zone never turns the real event loop. Wrap every real-IO section
  in `tester.runAsync(() async { ... })`. `_pumpApp` / `_seedScoredFile` build the
  whole app inside one `runAsync`.
- Actions triggered by a **tap** (save, close, choose-profile) run their IO in the
  fake zone, so a single `runAsync` isn't enough: `ScoreRepository.save` chains
  ~10 real IO steps (resolve folder → atomic write → reload → list → per-file
  read). The `_settle` helper loops `runAsync(15ms) + pumpAndSettle` ~24 times to
  drain the chain, then `pump(4s)` to dismiss SnackBars.
- Scores/ratings render via `Text.rich`, which `find.text` cannot match. Those
  widgets carry stable `ValueKey`s (`total-score`, `current-score`,
  `echo-score-<slot>`); read them with the `_plainText` helper
  (`RichText.text.toPlainText()`).
- The toolbar always shows the **active** file name, and both the NavRail item and
  the FilePanel header read `评分文件`. Scope file-list/nav assertions with
  `find.descendant(of: find.byType(FilePanel)/NavRail, ...)` (see `_panelFile`).
- Do **not** reintroduce an indeterminate `CircularProgressIndicator` on a path a
  test settles through — it makes `pumpAndSettle` hang forever.
- `Dialogs.promptText` keeps its `TextEditingController` in a `StatefulWidget`
  (`_TextPromptDialog`) and disposes it in `State.dispose`. Disposing right after
  `showDialog` returns throws "used after being disposed" during the dialog's
  exit animation — don't "simplify" it back.
- Tests run headless via `flutter_test`; there is no `integration_test/` and no
  golden-file tests.

## Repository conventions

- Commit messages use Conventional Commits (`chore:`, `feat:`, `fix:`) in
  lowercase.
- `.gitignore` excludes `.dart_tool/`, `/build/`, `/coverage/`, `.idea/`, and
  `*.iml`. `.idea/` and `mingchao_echo_scorer.iml` exist on disk but are
  intentionally untracked — do not `git add -A` them; stage files by name.
- `pubspec.lock` is committed; commit lockfile changes whenever deps change.
- Only commit when the user explicitly asks.
