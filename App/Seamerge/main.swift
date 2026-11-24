import AppKit
import Integration
import SeamergeUI
import SessionIPC

let application = NSApplication.shared
let delegate = AppDelegate(
  arguments: CommandLine.arguments, defaults: .standard,
  socketURL: SessionSocket.url(
    launchedWith: UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)),
  workStore: MergeWorkStore(folder: MergeWorkStore.standardFolder), pasteboard: .general,
  pastedTextCache: .standard, patchCache: .standard,
  presenter: ApplicationPresenter(),
  integrationStore: SystemIntegrationStore(
    bundle: Bundle.main.bundleURL, home: FileManager.default.homeDirectoryForCurrentUser),
  commandLineTool: CommandLineTool(bundle: Bundle.main.bundleURL), bundle: Bundle.main.bundleURL,
  updateServices: { NSUpdateDynamicServices() })
application.delegate = delegate
application.run()
