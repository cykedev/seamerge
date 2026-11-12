import AppKit
import SessionIPC

let application = NSApplication.shared
let delegate = AppDelegate(socketURL: SessionSocket.defaultURL, presenter: ApplicationPresenter())
application.delegate = delegate
application.run()
