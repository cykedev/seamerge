import Foundation

extension FileManager {
  /// Removes each item in `folder` that was made before `date`, as the copies of windows that a
  /// crash left behind; items made since stay, as those of a window that is open already.
  ///
  /// - Returns: The errors of the items that could not be removed.
  func removeItems(in folder: URL, madeBefore date: Date) -> [any Error] {
    let items: [URL]
    do {
      items = try contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])
    } catch {
      // A folder that was never made has nothing to remove.
      return []
    }
    var errors: [any Error] = []
    for item in items {
      do {
        let made = try item.resourceValues(forKeys: [.creationDateKey]).creationDate
        if made.map({ $0 < date }) ?? true {
          try removeItem(at: item)
        }
      } catch {
        errors.append(error)
      }
    }
    return errors
  }
}
