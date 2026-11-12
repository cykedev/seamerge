import AppKit
import SessionIPC

let application = NSApplication.shared
let delegate = AppDelegate(
  arguments: CommandLine.arguments, defaults: .standard, socketURL: SessionSocket.defaultURL,
  presenter: ApplicationPresenter())
application.delegate = delegate
application.run()
