import AppKit
import SeamergeUI
import SessionIPC

let application = NSApplication.shared
let delegate = AppDelegate(
  arguments: CommandLine.arguments, defaults: .standard, socketURL: SessionSocket.defaultURL,
  presenter: ApplicationPresenter(),
  integrationStore: SystemIntegrationStore(
    bundle: Bundle.main.bundleURL, home: FileManager.default.homeDirectoryForCurrentUser),
  commandLineTool: CommandLineTool(bundle: Bundle.main.bundleURL), bundle: Bundle.main.bundleURL,
  updateServices: { NSUpdateDynamicServices() })
application.delegate = delegate
application.run()
