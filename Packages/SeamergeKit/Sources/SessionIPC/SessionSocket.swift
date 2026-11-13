import Darwin
import Foundation

/// Where the app listens for the command-line tool.
public enum SessionSocket {
  /// The socket the app listens on: `seamerge.sock` in the folder `Seamerge` of the user's
  /// temporary folder.
  ///
  /// The temporary folder that the system keeps for each user lies below `/var/folders` and
  /// takes the same few characters for every user, whatever the home folder is called, so the
  /// path fits the 103 bytes a socket path may have. The app and the tool find the same folder
  /// without reading the environment, which Git may have changed.
  public static var defaultURL: URL {
    userTemporaryFolder.appending(
      components: "Seamerge", "seamerge.sock", directoryHint: .notDirectory)
  }

  /// The temporary folder that the system keeps for the user, or the temporary folder of
  /// Foundation if the system names none.
  private static var userTemporaryFolder: URL {
    let length = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
    guard length > 0 else { return FileManager.default.temporaryDirectory }
    var buffer = [CChar](repeating: 0, count: length)
    guard confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, length) == length else {
      return FileManager.default.temporaryDirectory
    }
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return URL(filePath: String(decoding: bytes, as: UTF8.self), directoryHint: .isDirectory)
  }
}
