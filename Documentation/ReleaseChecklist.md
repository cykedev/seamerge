# Release checklist

Work through this list in order before a release is tagged. The version number is set in one place, `App/Config/Version.xcconfig`; the app and the `seamerge` command read it from there, and `seamerge --version` prints it.

The project uses [Semantic Versioning](https://semver.org/). Before 1.0.0, a minor version may break the interface. The interface is the command line and exit codes of `seamerge`, the lines of the Git configuration it writes, the keys of its settings, and the public API of `MergeEngine`.

## Before the commit

- [ ] `Scripts/check.sh` exits with 0 on the commit that is about to be released. The output is the record for the release notes.
- [ ] `CHANGELOG.md` has a section for the version, in the format of Keep a Changelog, with the headings Added, Changed, Fixed and Removed. Every entry describes something that is in the release, and it is written for people who use Seamerge, not per commit.
- [ ] `Scripts/release-ready.sh` exits with 0. It checks the changelog section and the upstream branch.
- [ ] `App/Config/Version.xcconfig` holds the version and the build number is raised if the version is built again.

## Installation from a clean clone

- [ ] Clone the repository into a new folder, check out the release commit, and run `Scripts/install.sh --to <an empty folder>`. The app must start from that folder.
- [ ] Run `git mergetool` and `git difftool` with the scenarios that `Scripts/make-test-repo.sh` creates. A merge must save the result, and leaving it unresolved must keep the conflict.
- [ ] Set up the Git integration from the app and remove it again. Removing must leave the global configuration as it was before the set-up.

## Visual check

- [ ] The main windows look right in light and dark appearance, and with increased contrast.
- [ ] The screenshots used in the README and in `Documentation/UserGuide.md` still match the app. Replace any that do not, with images made from `Examples/`.

## Signing and notarization

- [ ] `Scripts/release.sh` builds, signs and notarizes the app. The downloaded app starts without a warning, and `spctl -a -vv` reports a notarized Developer ID.

## Commit and tag

- [ ] Commit the version and changelog as `chore(release): <version>`.
- [ ] Create an annotated tag `v<version>` on that commit. Do not push it until the checks above are complete.
- [ ] Publish the GitHub release with the changelog section as the release notes, and attach the signed, notarized app.
