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
  `AppPalette`), `io/transfer.dart` (choose folders / pick background images via
  `file_picker`).
- `lib/data/` — `catalog/` (built-in `SubstatType`, `tier_group` probability
  tables — **must stay built-in, no download**), `models/` (`ScoreFile`,
  `EchoEntry`, `Coefficients`, `CoefficientProfile`, `Rating`, `json_format`,
  `share_link`), `repositories/` (`StorageService`, `ScoreRepository`,
  `ProfileRepository`, `SettingsRepository`). Each score file is
  `<scores>/<name>/score.json`.
- `lib/domain/` — pure calculators, no Flutter/IO: `score_calculator.dart`,
  `expected_max_calculator.dart`, `probability_calculator.dart`.
- `lib/state/` — `ChangeNotifier` controllers (`WorkspaceController`,
  `ProfileController`, `SettingsController`) plus a plain `AppScope` container.
  Provided via `provider` in `main.dart`. No router: the shell switches views with
  the `ShellView` enum; modal pages (echo detail, profile editor) use
  `Navigator.push`.
- `lib/ui/` — `shell/` (`AppShell`, `NavRail`, `FilePanel`, `TopToolbar`,
  `FileListPage`), `overview/`, `detail/`, `profiles/`, `settings/`,
  `actions/` (`FileActions`, `ProfileActions`, `ShareActions` — glue between
  widgets and controllers), `widgets/` (`Dialogs`, `RatingChip`, `PageHeader`).
  Narrow screens (< `compactWidthBreakpoint`, i.e. Android) get a Material
  AppBar instead of `TopToolbar`: title = active file name + dirty dot, actions
  = 标签页 button (pushes the full-screen `FileListPage`: search + rows with
  inline share/rename/delete, tap a row to switch and pop), save, and a ⋮
  overflow holding the rest; the drawer holds `NavRail` only. `FilePanel` and
  `TopToolbar` are wide-only. Both narrow file ⋮ menus (AppBar + `FileListPage`)
  also carry 批量删除 (`FileActions.deleteMany` →
  `WorkspaceController.deleteFiles`, which rescans disk once for the whole batch
  and returns the entries that failed); the profiles page header folds
  从剪贴板导入配置 / 复制全部配置到剪贴板 / 批量删除 into one ⋮
  (`ValueKey('profiles-menu')`) beside the 新建配置 button. Multi-select goes
  through `Dialogs.pickMulti`, whose red 删除 button doubles as the confirm step
  (no second dialog). The wide `TopToolbar` only holds 保存 / 粘贴导入 / 复制链接 —
  新建 and 打开 live solely in `FilePanel` on the left, not duplicated in the
  toolbar. The overview page header shows the current 系数 name with a
  「更换系数」 button right beside it (`ValueKey('swap-profile')`); it reuses
  `FileActions.chooseProfile`, so switching re-snapshots coefficients and is
  picked up by `sameContentAs` dirty tracking.

Key invariants:
- **Derived data is never persisted.** Score, rating, expected-max, and
  probability are always recomputed from `tiers + coefficients`.
- **List grouping/order is a local UI preference only.** `LibraryLayout`
  (`lib/state/library_layout.dart`) persists a flat token sequence
  (`g:<组名>` headers / `p:<profileId>` / `s:<fileId>`) to prefs
  (`library.profileLayout` / `library.scoreLayout`). It never touches data
  models or `ShareLink`, and layout ops must not dirty files. Deleting a group
  header hoists its members to the root layer; 清空 deletes members instead.
  Dragging uses `ReorderableListView` + `onReorderItem` (Flutter 3.47:
  `onReorder` is deprecated), whose newIndex is post-removal — `moveNode`
  follows those coordinates.
- **Coefficients are snapshotted** into each `ScoreFile` when a profile is
  applied, so later profile edits don't silently rescore saved files.
- Accumulate at **full precision, round once** to 2 decimals for display
  (`ScoreCalculator.roundTo2`).
- `EchoEntry.sameContentAs` / `ScoreFile.sameContentAs` drive dirty tracking;
  keep them in sync when adding fields. NaN target scores compare equal.
- **Import/export goes through the clipboard, not file dialogs.** `ShareLink`
  (`lib/data/models/share_link.dart`) encodes `echoscorer://` + Base64(UTF-8 JSON),
  one item per `\n`-separated line; `ProfileShare` / `ScoreShare` wrap it per model.
  They tell the two kinds apart by whether the JSON has an `echoes` **list**, so
  pasting a profile link into the score importer (or vice versa) reports an
  explicit Chinese error instead of silently creating a bogus record. Parsing is
  deliberately lenient (whole-text pretty-printed JSON, bare single-line JSON,
  case-insensitive scheme, CRLF, URL-safe alphabet, stripped `=` padding) and a bad
  line is collected into `failures`, never fatal to the batch. Keep this file pure
  Dart (no Flutter import) so `test/share_link_test.dart` can cover it directly.
- Startup and save IO are batched for speed: `main()` calls `runApp` **before**
  the unawaited `bootstrap()`/`profiles.reload()` (the shell shows a spinner
  while `WorkspaceController.loading`); both repositories' `loadAll` read files
  concurrently; `saveAll` writes per file but rescans disk only once.

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
(choose folders, pick background images), `url_launcher` (GitHub link),
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
  They do run R8 (`isMinifyEnabled` + `isShrinkResources`) with the Flutter
  keep-rules in `android/app/proguard-rules.pro`; there is no device here to
  runtime-verify a minified release, so treat a release-only crash as an
  R8 suspect first.
- App version lives in `pubspec.yaml` (`version: 1.0.2+3`) and is mirrored by
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
- `uses-material-design: true`; Material icons only (`cupertino_icons` was an
  unused template leftover and is gone). No custom
  fonts or asset bundles are declared. The catalog data is compiled-in Dart, not
  an asset — adding assets requires extending the `flutter:` section of
  `pubspec.yaml`.

## Testing notes

- `test/` has pure-Dart unit tests (`score_calculator_test`, `rating_test`,
  `expected_max_test`, `probability_calculator_test`, `catalog_test`,
  `file_names_test`, `share_link_test`, `repositories/*_test`) plus
  `test/widget_test.dart` (23 end-to-end widget tests over the real UI).
  ~149 tests total.
- **Real `dart:io` futures hang if awaited directly in a `testWidgets` body** —
  the fake-async zone never turns the real event loop. Wrap every real-IO section
  in `tester.runAsync(() async { ... })`. `_pumpApp` / `_seedScoredFile` build the
  whole app inside one `runAsync`.
- Actions triggered by a **tap** (save, close, choose-profile) run their IO in the
  fake zone, so a single `runAsync` isn't enough: `ScoreRepository.save` chains
  ~10 real IO steps (resolve folder → atomic write → reload → list → per-file
  read). The `_settle` helper loops `runAsync(15ms) + pumpAndSettle` ~24 times to
  drain the chain, then `pump(4s)` to dismiss SnackBars.
- **`pumpAndSettle` advances the fake clock 100 ms per pump**, so looping it more
  than ~30 times fires a SnackBar's 3 s auto-dismiss Timer and the message you
  were about to assert on is already gone (and a Timer still pending at test end
  fails teardown). For batch imports — whose IO chain is much longer than a single
  save — use the condition-driven `_settleUntil(tester, () => ...)` instead of
  bumping `_settle`'s round count, and always end with `_dismissSnackBars`.
  When asserting on the result SnackBar of a batch action, make the *snack text*
  the `_settleUntil` condition: the controller notifies listeners before the
  action's continuation shows the snack, so a state-based condition stops one
  frame too early (the 删除 dialog is still on screen and eats the taps).
  `_drainSnack` is the lighter variant — real-event-loop passes plus 50 ms of fake
  time, never enough to trip the 3 s auto-dismiss.
- `flutter_test` has **no built-in Clipboard mock**. To exercise 复制 / 粘贴导入 end
  to end, register `setMockMethodCallHandler(SystemChannels.platform, ...)` and
  answer `Clipboard.setData` / `Clipboard.getData` yourself (see `_mockClipboard`).
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
