/// The connection of one command-line tool to the app, from the side of the app.
public final class SessionConnection: Sendable {
  /// What the tool asked for.
  public let request: SessionRequest

  private let connection: LineConnection
  private let endOfInput: Task<Void, Never>

  init(request: SessionRequest, connection: LineConnection, endOfInput: Task<Void, Never>) {
    self.request = request
    self.connection = connection
    self.endOfInput = endOfInput
  }

  /// Sends an event to the tool.
  ///
  /// - Throws: ``SessionError/disconnected`` if the tool is gone.
  public func send(_ event: SessionEvent) async throws(SessionError) {
    try await connection.write(MessageCoding.line(for: event))
  }

  /// Returns once the connection has ended.
  ///
  /// The connection ends when the tool closes it, for example because the user stopped it, when it
  /// sends anything after its request, and when the server stops.
  public func waitUntilDisconnected() async {
    await endOfInput.value
  }
}
