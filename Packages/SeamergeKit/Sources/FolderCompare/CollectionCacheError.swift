public import Foundation

/// Why the cache of collections could not keep a copy of a file.
public enum CollectionCacheError: Error, Sendable, Hashable {
  /// The side at the URL could not be copied into the cache.
  case copyFailed(URL)
}
