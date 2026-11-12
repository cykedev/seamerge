# Seamerge

Seamerge is a native diff and merge tool for macOS, written in Swift with AppKit and TextKit 2. It is meant to serve as the diff and merge tool for Git. The command-line interface is named `seamerge`.

**Status: in development.** There is no release yet and no installable app.

## Requirements

- macOS 27.0 or later
- Xcode 27. The checks were run with Xcode 27.2 (Swift 6.4.2).

The packages declare Swift tools version 6.2 and macOS 27.0 as their minimum.

## Building and checking

Clone the repository, then run the following in the clone:

```bash
git config core.hooksPath Scripts/git-hooks
Scripts/check.sh
```

`Scripts/check.sh` checks the format of all Swift files, then builds and tests each package under `Packages/`. It prints one line per step and exits with 0 only when every step passes. The full output is written to `.build/check.log`. Use `Scripts/check.sh --quick` to check the format and build without running the tests.

The `core.hooksPath` setting makes Git run the hooks in `Scripts/git-hooks`, which check the format of staged Swift files and the form of commit messages. The setting is local to each clone.

To build and test a single package:

```bash
swift test --package-path Packages/MergeEngine
```

## Layout

- `Packages/MergeEngine`: the diff and merge engine, with the vendored Perforce code and a Swift interface to it.
- `Packages/SeamergeKit`: the Swift modules of the app and the command-line tool.

## The diff and merge engine

The engine in `Packages/MergeEngine` is built on the Perforce Helix Core (p4) source, release 2025.1, patch 3079941, which is publicly available at <https://ftp.perforce.com/perforce/r25.1/bin.tools/p4source.tgz>. The vendored code lives in `Packages/MergeEngine/Sources/CMergeEngine/Vendor/Perforce`. [VENDORING.md](Packages/MergeEngine/VENDORING.md) describes the checksum, the files taken over and the changes made.

## License

Seamerge is licensed under the [MIT License](LICENSE).

The vendored Perforce code is third-party code under its own license, which is in [its license file](Packages/MergeEngine/Sources/CMergeEngine/Vendor/Perforce/LICENSE).
