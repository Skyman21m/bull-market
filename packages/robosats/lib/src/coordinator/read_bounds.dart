/// Hard bounds on what this package accepts from a coordinator, far above what an honest one sends, so that none can cost more than a fixed amount of memory and time.
abstract final class CoordinatorReadBounds {
  /// Bytes of a `/api/info/` body: about 1 KB, 2.3 KB with a long notice, on 10/11/2026.
  static const infoBytes = 65536;

  /// Bytes of a `/api/limits/` body: about 7.5 KB for 80 currencies.
  static const limitsBytes = 65536;

  /// Bytes of a `/api/book/` body: about 600 bytes per order, so several times [maxOrders].
  static const bookBytes = 4194304;

  /// Orders read from one book: a coordinator publishes at most `MAX_PUBLIC_ORDERS`, 100 in its sample configuration (`.env-sample:151`), and the rest of a longer book is left unread.
  static const maxOrders = 1000;

  /// Entries in `/api/limits/`: RoboSats has 80 currencies.
  static const maxLimitEntries = 500;

  /// Satoshis that can exist, the upper bound of every amount in sats.
  static const maxSats = 2100000000000000;
}
