# Contributing to Seamerge

Seamerge is in development, so interfaces and structure are still changing.

## Setup

Clone the repository and enable the Git hooks in the clone. The setting is local, so set it in every clone:

```bash
git config core.hooksPath Scripts/git-hooks
```

The build and test commands are in the [README](README.md#building-and-checking).

## Checks

`Scripts/check.sh` is the only check. The repository has no continuous integration, so run it yourself before you open a pull request. A change is ready when `Scripts/check.sh` exits with 0.

After the tests, `Scripts/check.sh` runs the tests of the engine and of the core modules once more under the address, undefined behaviour and thread sanitizers, so that memory errors in the bridge to C++ and data races in callbacks from threads fail the check as well. `Scripts/check.sh --quick` skips them, as it skips the tests. Their builds are kept in `.build/sanitize/` in the repository root.

Warnings in Swift code fail the build. The vendored Perforce code keeps its own warnings; `Scripts/check.sh` leaves them out of its output but still shows errors from that code.

## Formatting

The format is defined by `.swift-format` in the repository root: two spaces of indentation, lines of at most 100 characters, and the rules listed in that file. `Scripts/check.sh` lints with `swift format lint --strict`, so any finding fails the check. To format the Swift files in place, run:

```bash
swift format format --in-place --recursive Packages
```

## Commit messages

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): description`, with a lowercase scope. The allowed types are `build`, `chore`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor` and `test`. The subject line has at most 72 characters. The `commit-msg` hook rejects subjects that do not follow this form.

Keep each commit to one logical change. For example:

```
feat(syntax): describe the initial languages and detect them
```

## Pull requests

Pull requests use the template in [`.github/pull_request_template.md`](.github/pull_request_template.md): What, Why and How it was tested. Under How it was tested, state the result of `Scripts/check.sh`.

## Vendored code

The files in `Packages/MergeEngine/Sources/CMergeEngine/Vendor/Perforce` are third-party code from Perforce Software, Inc., licensed under their own terms (see the [license file](Packages/MergeEngine/Sources/CMergeEngine/Vendor/Perforce/LICENSE)). Changes to the engine belong outside that directory. A change to a vendored file needs a strong reason and is recorded in [VENDORING.md](Packages/MergeEngine/VENDORING.md) and in `Packages/MergeEngine/Patches/`.

## Tests

Tests use the Swift Testing framework (`import Testing`). Each module has a test target next to its sources.

## License

Contributions are accepted under the MIT License of this project.
