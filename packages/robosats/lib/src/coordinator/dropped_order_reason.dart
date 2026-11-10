/// Why an element of a book was left out: the field this package rejected, or a rule about the whole order.
///
/// Every value is a label of this package, never text from the coordinator.
enum DroppedOrderReason {
  /// The element is not a JSON object.
  notAnObject(null),
  id('id'),
  createdAt('created_at'),
  expiresAt('expires_at'),
  type('type'),
  currency('currency'),
  hasRange('has_range'),
  amount('amount'),
  minAmount('min_amount'),
  maxAmount('max_amount'),
  paymentMethod('payment_method'),
  isExplicit('is_explicit'),
  premium('premium'),
  satoshis('satoshis'),
  satoshisNow('satoshis_now'),
  price('price'),
  escrowDuration('escrow_duration'),
  bondSize('bond_size'),
  latitude('latitude'),
  longitude('longitude'),
  makerHashId('maker_hash_id'),
  makerNick('maker_nick'),
  makerStatus('maker_status'),

  /// Another element of the book has the same id: every copy is left out.
  duplicateId(null),

  /// The order does not match the currency or type the book was asked for.
  filterMismatch(null);

  /// The JSON field whose value was rejected, or `null` for a rule about the whole order.
  final String? field;

  const DroppedOrderReason(this.field);

  /// The reason for a field this package reads; any other name is a bug of this package.
  static DroppedOrderReason forField(String field) {
    for (final reason in values) {
      if (reason.field == field) return reason;
    }
    throw StateError('no DroppedOrderReason for the field $field');
  }
}
