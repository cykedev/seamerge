import Foundation
import SeamergeCLI

guard
  let executableURL = Bundle.main.executableURL,
  let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
else {
  preconditionFailure("The helper was built without its executable path or its version")
}
let command = SeamergeCommand(
  version: version, appLauncher: WorkspaceAppLauncher(executableURL: executableURL))
let result = await command.run(Array(CommandLine.arguments.dropFirst()))
result.write()
exit(result.exitStatus)
