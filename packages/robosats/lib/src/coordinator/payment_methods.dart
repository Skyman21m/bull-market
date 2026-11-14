import 'package:meta/meta.dart';
import 'package:robosats/src/coordinator/payment_method_data.dart';

/// A payment method or swap destination the official client recognises in the text of an order and shows with an icon.
@immutable
final class PaymentMethodInfo {
  /// The name, as the official client lists it in `components/PaymentMethods/MethodList.ts`.
  final String name;

  /// The icon key of the official client.
  final String icon;

  /// Whether the fiat payment can be reversed by the payer after the trade, which the official client warns about.
  final bool reversible;

  const PaymentMethodInfo(this.name, this.icon, {required this.reversible});

  @override
  bool operator ==(Object other) =>
      other is PaymentMethodInfo && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'PaymentMethodInfo($name)';
}

/// The payment methods of an order: free text chosen by the maker, at most 70 characters.
///
/// The maker picks methods from a list, which the official client joins with spaces, or types anything.
@immutable
final class PaymentMethods {
  /// The text as the coordinator sent it: maker text, to display as text only and never log.
  final String text;

  /// The methods the official client recognises in [text], in the order of its list.
  final List<PaymentMethodInfo> recognized;

  /// Whether [text] has words besides the recognised methods, which the official client shows as a generic icon.
  final bool hasOtherText;

  const PaymentMethods._(this.text, this.recognized, this.hasOtherText);

  /// The `not specified` entry, the default text of an order without methods.
  static const PaymentMethodInfo notSpecified = PaymentMethodInfo(
    'not specified',
    'notspecified',
    reversible: false,
  );

  /// The fiat payment methods the official client offers in its book filter, in the order of its list (`fiatMethods`, `frontend/src/components/MakerForm/AutocompletePayments.tsx:301` at commit ff1998c): a fixed list, whatever the orders of the book.
  static const List<PaymentMethodInfo> fiat = robosatsFiatMethods;

  /// Every recognised method: [notSpecified], the swap destinations and the fiat methods, in the order the official client tries them.
  static final List<PaymentMethodInfo> known = List.unmodifiable([
    notSpecified,
    ...robosatsSwapMethods,
    ...robosatsFiatMethods,
  ]);

  static final List<RegExp> _patterns = [
    for (final method in known)
      RegExp('\\b${RegExp.escape(method.name.toLowerCase())}\\b'),
  ];

  /// Characters the official client removes before matching (`components/PaymentMethods/StringAsIcons.tsx:30`).
  ///
  /// Its pattern matches surrogate pairs one UTF-16 unit at a time; here the same characters are written as code point ranges.
  static final RegExp _emoji = RegExp(
    r'[\u{2700}-\u{27BF}]|[\u{E000}-\u{F8FF}]|[\u{1F000}-\u{1F3FF}]|[\u{1F400}-\u{1F7FF}]|[\u{2011}-\u{26FF}]|[\u{1F910}-\u{1F9FF}]',
    unicode: true,
  );

  /// Recognises the methods in [text] as the official client does: a case-insensitive whole-word match of each name, emoji removed.
  ///
  /// Two deliberate differences: a name is matched literally (`Pouch.ph` does not match `Pouchxph`), and [hasOtherText] is computed by removing every recognised name and all whitespace, where the official client removes only some spaces.
  factory PaymentMethods.parse(String text) {
    final withoutEmoji = text.replaceAll(_emoji, '');
    final lower = withoutEmoji.toLowerCase();
    final recognized = <PaymentMethodInfo>[];
    var rest = lower;
    for (var i = 0; i < known.length; i++) {
      if (_patterns[i].hasMatch(lower)) {
        recognized.add(known[i]);
        rest = rest.replaceAll(_patterns[i], '');
      }
    }
    return PaymentMethods._(
      text,
      List.unmodifiable(recognized),
      rest.replaceAll(RegExp(r'\s'), '').isNotEmpty,
    );
  }

  /// Whether one of the recognised methods is reversible.
  bool get hasReversible => recognized.any((method) => method.reversible);

  @override
  bool operator ==(Object other) =>
      other is PaymentMethods && other.text == text;

  @override
  int get hashCode => text.hashCode;

  /// The recognised methods only: [text] is maker text.
  @override
  String toString() =>
      'PaymentMethods(${recognized.map((method) => method.name).join(', ')}${hasOtherText ? ', other' : ''})';
}
