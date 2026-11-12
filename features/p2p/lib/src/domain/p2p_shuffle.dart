/// The order in which the P2P screens show what has no order of its own: a new random order in the app, a fixed one in tests and screenshots.
///
/// It is given to the screens as `P2pClock` is, so that no widget draws at random by itself.
final class P2pShuffle {
  final List<int> Function(int count) _order;

  /// [order] gives the positions `0` to `count - 1`, each once, in the order to show them.
  const P2pShuffle(this._order);

  /// The app's: a new random order at each call.
  static const random = P2pShuffle(_random);

  /// The order given, unchanged, for tests and screenshots.
  static const unshuffled = P2pShuffle(_inOrder);

  /// The positions of [count] items, each once, in the order to show them; the order given when [_order] does not give each position once.
  List<int> positions(int count) {
    final order = _order(count);
    final isPermutation =
        order.length == count &&
        order.toSet().length == count &&
        order.every((position) => position >= 0 && position < count);
    return isPermutation ? List.unmodifiable(order) : _inOrder(count);
  }

  static List<int> _inOrder(int count) =>
      List<int>.unmodifiable(List<int>.generate(count, (i) => i));

  static List<int> _random(int count) =>
      List<int>.generate(count, (i) => i)..shuffle();
}
