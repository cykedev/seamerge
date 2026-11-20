extension Session {
  /// One value for each input of a session: always one for A and one for B, and one for the base
  /// in a merge that has a base.
  ///
  /// Iterating yields each value with its role, in the order base, A, B.
  public struct Inputs<Value> {
    /// The value of the base, or `nil` if the session has no base.
    public var base: Value?

    /// The value of A.
    public var a: Value

    /// The value of B.
    public var b: Value

    /// The values of `a` and `b`, and of `base` if there is one.
    public init(base: Value? = nil, a: Value, b: Value) {
      self.base = base
      self.a = a
      self.b = b
    }

    /// The value of `role`, or `nil` for the base of a session without one.
    public subscript(role: Role) -> Value? {
      switch role {
      case .base: base
      case .a: a
      case .b: b
      }
    }

    /// The inputs that take part, in the order base, A, B.
    public var roles: [Role] {
      base == nil ? [.a, .b] : [.base, .a, .b]
    }

    /// The values in the order base, A, B.
    public var values: [Value] {
      base.map { [$0, a, b] } ?? [a, b]
    }

    /// The inputs with `transform` applied to each value, in the order base, A, B; the first
    /// error ends the transformation.
    public func mapValues<Transformed, Failure>(
      _ transform: (Value) throws(Failure) -> Transformed
    ) throws(Failure) -> Inputs<Transformed> {
      let base = try base.map(transform)
      return Inputs<Transformed>(base: base, a: try transform(a), b: try transform(b))
    }

    /// The inputs with `transform` applied to each value and its role, in the order base, A, B;
    /// the first error ends the transformation.
    public func mapValuesWithRoles<Transformed, Failure>(
      _ transform: (Role, Value) throws(Failure) -> Transformed
    ) throws(Failure) -> Inputs<Transformed> {
      let base = try base.map { value throws(Failure) in try transform(.base, value) }
      return Inputs<Transformed>(base: base, a: try transform(.a, a), b: try transform(.b, b))
    }
  }
}

extension Session.Inputs: Sequence {
  /// The value of an input together with its role.
  public typealias Element = (role: Role, value: Value)

  /// An iterator over the inputs in the order base, A, B.
  public func makeIterator() -> IndexingIterator<[Element]> {
    let sides: [Element] = [(.a, a), (.b, b)]
    return (base.map { [(.base, $0)] + sides } ?? sides).makeIterator()
  }
}

extension Session.Inputs: Sendable where Value: Sendable {}

extension Session.Inputs: Equatable where Value: Equatable {}
