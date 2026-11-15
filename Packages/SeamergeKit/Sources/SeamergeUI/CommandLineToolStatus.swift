import Foundation

/// What lies at the place of the seamerge command, and whether this copy of Seamerge can put its
/// link there.
struct CommandLineToolStatus: Sendable, Equatable {
  /// What lies at the place of the command.
  enum Entry: Sendable, Equatable {
    /// Nothing, and Homebrew did not install the command either.
    case none

    /// A link to the helper of this copy.
    case thisCopy

    /// A link to the helper of another copy of Seamerge, which may be gone, at `app`.
    case otherCopy(app: String)

    /// A link that Homebrew made when it installed Seamerge.
    case homebrew

    /// A file that is not a link to Seamerge: a link to `destination`, or something else if
    /// `destination` is `nil`. It is never replaced or removed.
    case otherFile(destination: String?)
  }

  /// What lies at the place of the command.
  var entry: Entry

  /// The place of the command.
  var link: URL

  /// The helper of this copy, which the link names.
  var helper: URL

  /// Whether the folder of the link exists; installing creates it if not.
  var hasLinkFolder: Bool

  /// Why this copy cannot put its link there, or `nil` if it can.
  var problem: AppLocation.Problem?
}

/// Where the seamerge command goes, and where Homebrew puts it.
struct CommandLinePlace: Sendable {
  /// The link that puts the command into the `PATH`.
  let link: URL

  /// The folders Homebrew can be installed in, each with its own `bin` and `Caskroom`.
  let homebrewPrefixes: [URL]

  /// The end of the path of the helper in every bundle of Seamerge.
  static let helperSuffix = ".app/Contents/Helpers/seamerge"

  /// What lies at the place of the command, as the file system says, for the copy at
  /// `location`.
  func status(for location: AppLocation) -> CommandLineToolStatus {
    let entry: CommandLineToolStatus.Entry
    switch Self.item(at: link) {
    case .missing:
      entry = homebrewLink() != nil ? .homebrew : .none
    case .symbolicLink(let destination):
      if homebrewLink() == link.standardizedFileURL {
        entry = .homebrew
      } else if Self.names(destination, theSameFileAs: location.helper) {
        entry = .thisCopy
      } else if destination.path.hasSuffix(Self.helperSuffix) {
        entry = .otherCopy(
          app: String(destination.path.dropLast(Self.helperSuffix.count - ".app".count)))
      } else {
        entry = .otherFile(destination: destination.path)
      }
    case .other:
      entry = .otherFile(destination: nil)
    }
    var isFolder: ObjCBool = false
    let hasLinkFolder =
      FileManager.default.fileExists(
        atPath: link.deletingLastPathComponent().path, isDirectory: &isFolder) && isFolder.boolValue
    return CommandLineToolStatus(
      entry: entry, link: link, helper: location.helper, hasLinkFolder: hasLinkFolder,
      problem: location.problem)
  }

  /// The link of the command that Homebrew made, if Homebrew installed Seamerge.
  private func homebrewLink() -> URL? {
    homebrewPrefixes.lazy.compactMap { prefix -> URL? in
      let link = prefix.appending(path: "bin/seamerge").standardizedFileURL
      let caskroom = prefix.appending(path: "Caskroom/seamerge").path
      guard FileManager.default.fileExists(atPath: caskroom),
        case .symbolicLink = Self.item(at: link)
      else { return nil }
      return link
    }.first
  }

  /// What a path names, without following a link at its end.
  private enum Item {
    case missing
    case symbolicLink(destination: URL)
    case other
  }

  private static func item(at url: URL) -> Item {
    let path = url.path
    let attributes: [FileAttributeKey: Any]
    do {
      attributes = try FileManager.default.attributesOfItem(atPath: path)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return .missing
    } catch {
      // What cannot be read is treated as a file of someone else, which is never touched.
      return .other
    }
    guard attributes[.type] as? FileAttributeType == .typeSymbolicLink else { return .other }
    do {
      let destination = try FileManager.default.destinationOfSymbolicLink(atPath: path)
      let absolute =
        destination.hasPrefix("/")
        ? URL(filePath: destination)
        : url.deletingLastPathComponent().appending(path: destination)
      return .symbolicLink(destination: absolute.standardizedFileURL)
    } catch {
      return .other
    }
  }

  /// Whether `destination` and `helper` are the same file, also where one of them goes through a
  /// link such as `/tmp`.
  private static func names(_ destination: URL, theSameFileAs helper: URL) -> Bool {
    destination.standardizedFileURL.path == helper.standardizedFileURL.path
      || destination.resolvingSymlinksInPath().path == helper.resolvingSymlinksInPath().path
  }
}
