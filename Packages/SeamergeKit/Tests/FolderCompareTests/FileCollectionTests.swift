import FolderCompare
import FolderCompareTestSupport
import Foundation
import GitSupport
import MergeModel
import Testing

/// The files of a collection: their order, the end of receiving, and the copies they keep.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct FileCollectionTests {
  private let origin = CollectionOrigin(repository: "/repository", run: nil)

  @Test func filesKeepTheOrderOfGitWhateverOrderTheyComeIn() throws {
    let files = try SampleCollections.many(5, in: try SampleCollections.folder())
    let collection = FileCollection(origin: origin, expectedCount: 5, quietPeriod: .seconds(60))

    for index in [2, 0, 4, 1] {
      collection.add(files[index])
    }

    #expect(collection.files.map(\.path) == [0, 1, 2, 4].map { files[$0].path })
    #expect(collection.isReceiving)
  }

  @Test func filesWithoutNumbersArePutInTheOrderOfTheirPaths() throws {
    let folder = try SampleCollections.folder()
    let collection = FileCollection(origin: origin, expectedCount: nil, quietPeriod: .seconds(60))

    for path in ["b/file10.txt", "a.txt", "b/file9.txt"] {
      collection.add(try SampleCollections.file(path, old: "1\n", new: "2\n", in: folder))
    }

    #expect(collection.files.map(\.path) == ["a.txt", "b/file9.txt", "b/file10.txt"])
  }

  @Test func receivingEndsOnceEveryNumberHasCome() throws {
    let files = try SampleCollections.many(3, in: try SampleCollections.folder())
    let collection = FileCollection(origin: origin, expectedCount: 3, quietPeriod: .seconds(60))
    var changes: [FileCollection.Change] = []
    collection.onChange = { changes.append($0) }

    for file in files {
      #expect(collection.accepts(origin))
      collection.add(file)
    }

    #expect(!collection.isReceiving)
    #expect(!collection.accepts(origin))
    #expect(changes == [.inserted(0), .inserted(1), .inserted(2), .complete])
  }

  @Test func callOfAnotherOriginDoesNotJoin() {
    let collection = FileCollection(origin: origin, expectedCount: nil, quietPeriod: .seconds(60))

    #expect(!collection.accepts(CollectionOrigin(repository: "/other", run: nil)))
    #expect(
      !collection.accepts(
        CollectionOrigin(repository: "/repository", run: ProcessRun(processID: 1, startTime: 2))))
  }

  @Test func fileOfACallThatJoinedIsAddedAfterReceivingEnded() throws {
    let files = try SampleCollections.many(2, in: try SampleCollections.folder())
    let collection = FileCollection(origin: origin, expectedCount: nil, quietPeriod: .seconds(60))
    collection.add(files[0])

    collection.endReceiving()
    collection.add(files[1])

    #expect(collection.files.count == 2)
    #expect(!collection.isReceiving)
  }

  @Test func receivingEndsWhenTheRunOfGitEnds() async throws {
    let process = Process()
    process.executableURL = URL(filePath: "/bin/cat")
    let input = Pipe()
    process.standardInput = input
    try process.run()
    let run = try #require(ProcessRun(processID: process.processIdentifier))
    let collection = FileCollection(
      origin: CollectionOrigin(repository: "/repository", run: run), expectedCount: 40)
    let ended = AsyncStream.makeStream(of: Void.self)
    collection.onChange = { if $0 == .complete { ended.continuation.yield() } }
    #expect(collection.isReceiving)

    try input.fileHandleForWriting.close()
    process.waitUntilExit()
    var iterator = ended.stream.makeAsyncIterator()
    await iterator.next()

    #expect(!collection.isReceiving)
  }

  @Test func receivingWithoutTheRunEndsAfterAQuietPeriod() async throws {
    let files = try SampleCollections.many(3, in: try SampleCollections.folder())
    let collection = FileCollection(
      origin: origin, expectedCount: 3, quietPeriod: .milliseconds(10))
    let ended = AsyncStream.makeStream(of: Void.self)
    collection.onChange = { if $0 == .complete { ended.continuation.yield() } }

    collection.add(files[0])
    var iterator = ended.stream.makeAsyncIterator()
    await iterator.next()

    #expect(!collection.isReceiving)
    #expect(collection.files.count == 1)
  }

  @Test func runThatEndedBeforeEndsReceivingAtOnce() {
    let collection = FileCollection(
      origin: CollectionOrigin(
        repository: "/repository", run: ProcessRun(processID: getpid(), startTime: 1)),
      expectedCount: 40)

    #expect(!collection.isReceiving)
  }

  @Test func copiesOfTemporaryFilesStayReadableAndGoWithTheirFolder() async throws {
    let folder = try SampleCollections.folder()
    let workingTree = folder.appending(path: "repository", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: workingTree, withIntermediateDirectories: true)
    let workingCopy = workingTree.appending(path: "a.txt")
    try Data("new\n".utf8).write(to: workingCopy)
    let temporary = try SampleCollections.file("a.txt", old: "old\n", new: nil, in: folder)
    let file = CollectedFile(
      old: temporary.old, new: SessionFile(url: workingCopy, label: "a.txt"),
      difftool: DifftoolContext(path: "a.txt", rightRole: .workingCopy))
    let cache = CollectionCache(folder: folder.appending(path: "cache"))
    let collectionFolder = cache.makeFolder()

    let kept = try await cache.keep(file, in: collectionFolder, workingTree: workingTree)
    try FileManager.default.removeItem(at: file.old.url)

    #expect(kept.new.url == workingCopy)
    #expect(kept.old.url.path.hasPrefix(collectionFolder.path))
    #expect(try String(contentsOf: kept.old.url, encoding: .utf8) == "old\n")
    cache.remove(collectionFolder)
    #expect(!FileManager.default.fileExists(atPath: collectionFolder.path))
  }

  @Test func missingSideIsNotCopied() async throws {
    let folder = try SampleCollections.folder()
    let file = try SampleCollections.file("new.txt", old: nil, new: "new\n", in: folder)
    let cache = CollectionCache(folder: folder.appending(path: "cache"))

    let kept = try await cache.keep(file, in: cache.makeFolder(), workingTree: folder)

    #expect(kept.old.url == URL(filePath: "/dev/null"))
    #expect(kept.change == .added)
  }

  @Test func sideThatCannotBeCopiedIsNamedInTheError() async throws {
    let folder = try SampleCollections.folder()
    let file = try SampleCollections.file("a.txt", old: "old\n", new: "new\n", in: folder)
    let blocked = folder.appending(path: "blocked")
    try Data().write(to: blocked)
    let cache = CollectionCache(folder: folder.appending(path: "cache"))

    await #expect(throws: CollectionCacheError.copyFailed(file.old.url)) {
      try await cache.keep(file, in: blocked, workingTree: folder.appending(path: "repository"))
    }
  }

  @Test func copiesLeftBehindByACrashGoAtOnce() throws {
    let folder = try SampleCollections.folder()
    let cache = CollectionCache(folder: folder.appending(path: "cache"))
    let left = cache.makeFolder()
    try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)

    cache.removeAll()

    #expect(!FileManager.default.fileExists(atPath: cache.folder.path))
  }
}
