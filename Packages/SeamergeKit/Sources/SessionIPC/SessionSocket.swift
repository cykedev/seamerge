import Foundation

/// Where the app listens for the command-line tool.
public enum SessionSocket {
  /// The socket the app listens on: `seamerge.sock` in the app's folder in Application Support.
  public static var defaultURL: URL {
    URL.applicationSupportDirectory.appending(components: "Seamerge", "seamerge.sock")
  }
}
