// SessionIPC is the protocol between the command-line tool and the running
// app: the messages that open a comparison or a merge and report its outcome,
// and the Unix-socket connection that carries them.
import os

extension Logger {
  /// The log of the exchange between the command-line tool and the app.
  static let sessionIPC = Logger(subsystem: "app.eiden.seamerge", category: "SessionIPC")
}
