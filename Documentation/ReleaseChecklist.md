# Release checklist

Work through this list in order before a release is tagged. The version number is set in one place, `App/Config/Version.xcconfig`; the app and the `seamerge` command read it from there, and `seamerge --version` prints it.

The project uses [Semantic Versioning](https://semver.org/). Before 1.0.0, a minor version may break the interface. The interface is the command line and exit codes of `seamerge`, the lines of the Git configuration it writes, the keys of its settings, and the public API of `MergeEngine`.

## Before the commit

- [ ] `Scripts/check.sh` exits with 0 on the commit that is about to be released. The output is the record for the release notes.
- [ ] `CHANGELOG.md` has a section for the version, in the format of Keep a Changelog, with the headings Added, Changed, Fixed and Removed. Every entry describes something that is in the release, and it is written for people who use Seamerge, not per commit.
- [ ] `Scripts/release-ready.sh` exits with 0. It checks the changelog section and the upstream branch.
- [ ] `App/Config/Version.xcconfig` holds the version, and `CURRENT_PROJECT_VERSION` is one higher than in the previous release. Sparkle compares this build number, so it must rise with every release and never reset.

## Installation from a clean clone

- [ ] Clone the repository into a new folder, check out the release commit, and run `Scripts/install.sh --to <an empty folder>`. The app must start from that folder.
- [ ] Run `git mergetool` and `git difftool` with the scenarios that `Scripts/make-test-repo.sh` creates. A merge must save the result, and leaving it unresolved must keep the conflict.
- [ ] Set up the Git integration from the app and remove it again. Removing must leave the global configuration as it was before the set-up.

## Visual check

- [ ] The main windows look right in light and dark appearance, and with increased contrast.
- [ ] The screenshots used in the README and in `Documentation/UserGuide.md` still match the app. Replace any that do not, with images made from `Examples/`.

## Signing and notarization

- [ ] `Scripts/release.sh <keychain-profile>` builds, signs and notarizes the app, and writes `Seamerge-<version>.zip`, `Seamerge-<version>.dmg` and `appcast.xml` to `.build/release/<version>/`. The profile is the one that `xcrun notarytool store-credentials` created. The downloaded app starts without a warning, and `spctl -a -vv` reports a notarized Developer ID.
- [ ] The Sparkle key that signs the appcast is in the login Keychain, and a backup is in the password manager. To restore it on another Mac, run `generate_keys -f <file>` from `.build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin/`; `Scripts/check.sh --quick` creates that folder. Installed copies check updates against the public key in `App/Config/Info.plist`, so the key must stay the same from release to release.
- [ ] `generate_appcast` may ask for access to the Keychain. Allow it only on the Mac that makes the release.

## Feed and privacy policy

- [ ] Upload `Seamerge-<version>.zip`, `Seamerge-<version>.dmg` and `appcast.xml` together to the GitHub release `v<version>`, and publish that release as the latest one. The feed is `https://github.com/cykedev/seamerge/releases/latest/download/appcast.xml`; `https://www.seamerge.app/appcast.xml` redirects to it.
- [ ] `curl --location --silent --output /dev/null --write-out '%{http_code}\n' https://www.seamerge.app/appcast.xml` prints `200`.
- [ ] The privacy policy at `https://www.seamerge.app/about.html` has the section "Update check in the app" and is online before the tag is created.
- [ ] An installed copy of the previous release offers the new version under **Seamerge ▸ Check for Updates…**, and **Install and Relaunch** installs it.

## Commit and tag

- [ ] Commit the version and changelog as `chore(release): <version>`.
- [ ] Create an annotated tag `v<version>` on that commit. Do not push it until the checks above are complete.
- [ ] Publish the GitHub release with the changelog section as the release notes, and attach the signed, notarized app.

## Homebrew cask

The cask lives in the tap `cykedev/homebrew-tap`, a clone of which the release script writes into.

- [ ] Before the build, `Scripts/release.sh` checks that `CURRENT_PROJECT_VERSION` is higher than every build number in the feed online, and stops with the reason if it is not.
- [ ] `Scripts/release.sh <keychain-profile> --tap <tap-folder>` writes `Casks/seamerge.rb` into the tap clone, with the version and the SHA-256 of the zip. To write the cask again for a version that is already built, run `Scripts/release.sh --cask --tap <tap-folder>`; it needs the zip in `.build/release/<version>/`.
- [ ] After the GitHub release is published, commit and push `Casks/seamerge.rb` in the tap clone. The script leaves that to you.
- [ ] After the push, run `brew style cykedev/tap` and `brew audit --cask --strict --online cykedev/tap/seamerge`, and check that `brew install --cask cykedev/tap/seamerge` installs the new version.
