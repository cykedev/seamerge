import Foundation
import GitSupport
import Testing

/// Finding `git` without starting the stand-in of the developer tools.
struct GitInstallationTests {
  @Test func gitOnTheSearchPathIsInstalled() throws {
    try withSandbox { sandbox in
      let git = try sandbox.makeExecutable("git", script: "exit 0")

      let found = Git.installed(environment: ["PATH": git.deletingLastPathComponent().path])

      #expect(found?.executableURL == git)
    }
  }

  @Test func standInWithoutDeveloperToolsIsNotInstalled() throws {
    try withSandbox { sandbox in
      let found = Git.installed(environment: ["PATH": "", "DEVELOPER_DIR": sandbox.directory.path])

      #expect(found == nil)
    }
  }

  @Test func standInWithDeveloperToolsIsInstalled() throws {
    try withSandbox { sandbox in
      _ = try sandbox.makeExecutable("git", in: "Developer/usr/bin", script: "exit 0")
      let developer = sandbox.directory.appending(path: "Developer").path

      let found = Git.installed(environment: ["PATH": "", "DEVELOPER_DIR": developer])

      #expect(found?.executableURL == URL(filePath: "/usr/bin/git"))
    }
  }
}
