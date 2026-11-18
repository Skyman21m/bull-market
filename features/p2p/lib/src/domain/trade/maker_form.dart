import 'package:meta/meta.dart';
import 'package:robosats/robosats.dart';

import 'exact_ratio.dart';
import 'maker_terms.dart';
import 'trade_make.dart';

/// A number typed in a field of the create form (#181): the text read once, by one rule, so that what the summary shows and what the request sends are the same value.
///
/// The reference reads its fields as `type='number'` inputs (`components/MakerForm/MakerForm.tsx:875-901`, `:1030-1049`, commit ff1998c), which the browser keeps to a plain decimal number; here the text is read as such a number and nothing else:
/// - spaces at either end are ignored; a space, a letter or a sign `+` inside makes it no number;
/// - a comma is read as the decimal separator as well as a point, as the take's amount field reads it (`TakeAmountInput`), and only one separator is allowed, so `1,000.5` and `1.000,5` are no numbers rather than guesses;
/// - the digits of the Arabic-Indic, the Extended Arabic-Indic (Persian) and the Devanagari scripts, and the full-width digits, are read as their values, the Arabic decimal separator (U+066B) and the full-width full stop (U+FF0E) as a point, the full-width comma (U+FF0C) as a comma; any other character is no number;
/// - `NaN`, `Infinity`, an exponent, a hexadecimal number, a figure that is not finite once read, more than [maxLength] characters or more decimals than the field keeps are no number, and so is a number that a double cannot hold as it is written (it would be read, shown and sent as its nearest double);
/// - a minus sign is read (a negative premium is a discount); `-0` is 0.
@immutable
sealed class FormNumber {
  const FormNumber();

  /// The most characters a field takes, as the take's amount field (`LengthLimitingTextInputFormatter(20)`).
  static const int maxLength = 20;

  /// What [text] says, with at most [maxDecimals] decimals.
  static FormNumber read(String text, {required int maxDecimals}) =>
      _read(text, maxDecimals: maxDecimals, checkRoundTrip: true);

  static FormNumber _read(
    String text, {
    required int maxDecimals,
    required bool checkRoundTrip,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const FormNumberEmpty();
    if (trimmed.length > maxLength) return const FormNumberInvalid();
    final latin = StringBuffer();
    for (final rune in trimmed.runes) {
      latin.write(_latin(rune) ?? String.fromCharCode(rune));
    }
    final written = latin.toString();
    final match = _number.firstMatch(written);
    if (match == null) return const FormNumberInvalid();
    final whole = match.group(1) ?? '';
    final fraction = match.group(2) ?? '';
    if (whole.isEmpty && fraction.isEmpty) return const FormNumberInvalid();
    if (fraction.length > maxDecimals) return const FormNumberInvalid();
    final sign = written.startsWith('-') ? '-' : '';
    final value = double.tryParse(
      '$sign${whole.isEmpty ? '0' : whole}${fraction.isEmpty ? '' : '.$fraction'}',
    );
    if (value == null || !value.isFinite) return const FormNumberInvalid();
    if (checkRoundTrip && !_roundTrips(whole, fraction, value)) {
      return const FormNumberInvalid();
    }
    return FormNumberValue(value == 0 ? 0.0 : value);
  }

  /// Whether [value] is written back exactly as its digits were typed, [whole] and [fraction], so that what the field shows, what the summary shows and what is sent are one number (security review of #181): `100000000.00000002` reads as the nearest double, which writes `100000000.00000001`, and is refused.
  static bool _roundTrips(String whole, String fraction, double value) {
    final digits = whole.replaceFirst(RegExp('^0+'), '');
    final typed =
        '${digits.isEmpty ? '0' : digits}${fraction.isEmpty ? '' : '.$fraction'}';
    return value.abs().toStringAsFixed(fraction.length) == typed;
  }

  /// Whether [text] is a plain decimal number that a double cannot hold as it is written (see [read]): the field takes no such edit.
  static bool beyondPrecision(String text, {required int maxDecimals}) {
    if (read(text, maxDecimals: maxDecimals) is! FormNumberInvalid) {
      return false;
    }
    final unchecked = _read(
      text,
      maxDecimals: maxDecimals,
      checkRoundTrip: false,
    );
    return unchecked is FormNumberValue;
  }

  /// A plain decimal number: an optional minus, digits, and one separator with its decimals, or a separator and decimals; the whole part is the first group, the decimals the second.
  static final RegExp _number = RegExp(r'^-?(\d+)?(?:[.,](\d*))?$');

  /// The ASCII digit or point a code point is written for, or `null` for any other.
  static String? _latin(int rune) {
    for (final zero in const [0x0660, 0x06F0, 0x0966, 0xFF10]) {
      if (rune >= zero && rune <= zero + 9) return '${rune - zero}';
    }
    if (rune == 0x066B || rune == 0xFF0E) return '.';
    if (rune == 0xFF0C) return ',';
    return null;
  }

  /// The value, or `null` when nothing or no number is typed.
  double? get value => switch (this) {
    FormNumberValue(:final value) => value,
    _ => null,
  };
}

/// Nothing typed, or only spaces.
final class FormNumberEmpty extends FormNumber {
  const FormNumberEmpty();
}

/// Something typed that is no number (see [FormNumber]).
final class FormNumberInvalid extends FormNumber {
  const FormNumberInvalid();
}

/// A number: [value] is finite.
final class FormNumberValue extends FormNumber {
  @override
  final double value;

  const FormNumberValue(this.value);
}

/// A payment method the user types with « Add custom payment method » (`Dialogs/AddNewPaymentMethodDialog.tsx`, commit ff1998c), as the form keeps it.
///
/// The reference keeps whatever is typed but an empty field (« Can't be empty »). Here the text the form keeps is what other robots will see (#181, from the security review of #194): an ideographic space becomes an ordinary one, spaces at its ends are taken off and a run of spaces inside becomes one, so the method shown is the method sent; then it must be seen as it is written ([isShownAsWritten] of `package:robosats`: never a text that shows as empty, nor one with an invisible character, a space other than U+0020, a private use character, or a joiner, a variation selector or a combining mark out of place). Its length is judged with the other methods, as the reference judges the text of them all (« Must be shorter than 65 characters » above [maxLength], `MakerForm.tsx:227`, `:995-999`).
@immutable
final class CustomPaymentMethod {
  /// The longest text of the methods chosen, in UTF-16 units, as the reference counts (`paymentMethodText.length > 50`).
  static const int maxLength = 50;

  /// The text kept.
  final String text;

  const CustomPaymentMethod._(this.text);

  /// The method of [typed], or `null` when nothing is left once its spaces are taken off ([isEmpty]) or what is left is not seen as written.
  static CustomPaymentMethod? tryCreate(String typed) {
    final text = keptOf(typed);
    if (text.isEmpty || !isShownAsWritten(text)) return null;
    return CustomPaymentMethod._(text);
  }

  /// [typed] as the form would keep it: the ideographic space (U+3000, which a Japanese or Chinese keyboard types in full width) made an ordinary one, its ends' spaces taken off, each run of spaces inside made one.
  static String keptOf(String typed) =>
      typed.replaceAll('\u3000', ' ').trim().replaceAll(RegExp(' {2,}'), ' ');

  /// Whether [a] and [b] are one method to a reader: equal once their joiners (U+200C, U+200D) and variation selectors are taken off, so that the form never adds one twice (security review of #181).
  static bool sameMethod(String a, String b) => _bare(a) == _bare(b);

  static String _bare(String text) => String.fromCharCodes(
    text.runes.where(
      (rune) =>
          rune != 0x200C &&
          rune != 0x200D &&
          !(rune >= 0xFE00 && rune <= 0xFE0F) &&
          !(rune >= 0xE0100 && rune <= 0xE01EF),
    ),
  );

  /// Whether nothing is left of [typed] once its spaces are taken off: the reference's « Can't be empty ».
  static bool isEmpty(String typed) => keptOf(typed).isEmpty;
}

/// What the create form asks of the coordinator chosen: its `/api/limits/`, read anonymously.
@immutable
sealed class MakerFormLimits {
  const MakerFormLimits();
}

/// The limits are being read, or no coordinator is chosen yet.
final class MakerFormLimitsLoading extends MakerFormLimits {
  const MakerFormLimitsLoading();
}

/// The limits could not be read.
final class MakerFormLimitsUnreadable extends MakerFormLimits {
  const MakerFormLimitsUnreadable();
}

/// The limits read.
final class MakerFormLimitsRead extends MakerFormLimits {
  final CurrencyLimits limits;

  const MakerFormLimitsRead(this.limits);
}

/// Why « Create order » is disabled, in the order the reference says it (`getDisabledMessage`, `MakerForm.tsx:517-565`): one reason, the first that applies.
///
/// The reason of the reference's legacy mode cannot apply to this form and is left out; [sellComingLater] is the app's own.
enum MakerFormBlock {
  /// « Loading coordinator list... »: the default coordinator is not drawn yet.
  loadingCoordinators,

  /// « The Bitcoin price is not synchronized. »: the coordinator's limits are being read, or give no usable price for the currency.
  priceNotSynchronized,

  /// « The coordinator limits are not available. »: they could not be read. The reference checks it after the premium (`:552-554`), but without limits no amount can be judged, and while they are missing it says the price is not synchronized (`:524-526`): here the failure is said at once, in the reference's words.
  limitsUnavailable,

  /// « Please select if you want to buy or sell. »
  noSide,

  /// « Selling as maker is coming in a later version. » (the app's own): the side is « Sell », which the form never lets the user choose.
  sellComingLater,

  /// « The amount is outside the allowed limits. »
  amountOutsideLimits,

  /// « The payment method is not valid. »: the methods' text is longer than 50 UTF-16 units.
  badPaymentMethod,

  /// « Please enter an amount. »: nothing typed, or no number, for an exact amount (a range has its own reason, as the reference's `maker.amount == null && !makerHasAmountRange`, `:540-542`).
  noAmount,

  /// « The amount range is not valid. » (#183): a bound of the range missing, out of the form's limits, or the range's ratio outside [MakerFormCheck.minRangeRatio] to [MakerFormCheck.maxRangeRatio] (`AmountRange.tsx:57-77`, `MakerForm.tsx:543-545`).
  amountRangeInvalid,

  /// « The amount must be greater than 0. »
  amountNotPositive,

  /// « The premium is not valid. »: above 999 % or at most −100 %.
  premiumInvalid,

  /// « The premium must be a number. »: something typed that is no number (an empty premium is 0, « at market price »).
  premiumNotANumber,

  /// « Please select a payment method. »
  noPaymentMethod,

  /// « The description is not valid. » (#183): longer than [MakerFormCheck.maxDescriptionLength] UTF-16 units (`MakerForm.tsx:359-365`, `:561-563`), or, the app's own, a text others would not see as it is written ([OrderDescription]).
  descriptionInvalid,

  /// « You must fill the form correctly »: what the package refuses to send although every rule above passed.
  formIncorrect,
}

/// What the amount field says under itself (`MakerForm.tsx:883-893`): « Must be more than {{minAmount}} » or « Must be less than {{maxAmount}} », the bound shown to 2 significant digits as the reference writes it (`toPrecision(2)`).
@immutable
sealed class MakerAmountProblem {
  /// The bound to show, rounded to 2 significant digits.
  final double shown;

  const MakerAmountProblem(this.shown);
}

final class MakerAmountTooLow extends MakerAmountProblem {
  const MakerAmountTooLow(super.shown);
}

final class MakerAmountTooHigh extends MakerAmountProblem {
  const MakerAmountTooHigh(super.shown);
}

/// What the premium field says under itself (`MakerForm.tsx:241-247`): « Must be less than {{max}}% » above 999, « Must be more than {{min}}% » at −100 or below.
enum MakerPremiumProblem { tooHigh, tooLow }

/// The maker's « Description » (#183, `MakerForm.tsx:359-365`, `:1051-1083`), as the form keeps it: what others will read on the order and on Nostr.
///
/// The reference sends what is typed, or `null` when nothing is (`description: maker.description ? maker.description : null`, `:274`), and the coordinator's serializer trims its ends. Here the text kept is the one the coordinator stores, so that the order read back is compared with it as sent (`MakeOrderRequest` refuses a text with spaces at its ends): an ideographic space made an ordinary one, as for a custom payment method (#181), and the ends' spaces taken off; nothing else changed, the spaces inside kept. It must then be seen as it is written ([isShownAsWritten] of `package:robosats`: no line break, control, invisible character or mark out of place), which the reference does not check (the app's own, as for the payment methods since #181).
@immutable
final class OrderDescription {
  const OrderDescription._();

  /// The description [typed] as it is sent: `null` when nothing is left once its ends' spaces are taken off.
  static String? keptOf(String typed) {
    final kept = typed.replaceAll('\u3000', ' ').trim();
    return kept.isEmpty ? null : kept;
  }

  /// Whether [typed] is longer than the reference allows: [MakerFormCheck.maxDescriptionLength] UTF-16 units, as it counts (`event.target.value.length > 240`, `:363`), so never more code points than the coordinator's `max_length` (`api/models/order.py:178-184`).
  static bool tooLong(String typed) =>
      typed.length > MakerFormCheck.maxDescriptionLength;

  /// Whether what [typed] keeps ([keptOf]) would not be seen by others as it is written.
  static bool notShownAsWritten(String typed) => switch (keptOf(typed)) {
    final kept? => !isShownAsWritten(kept),
    null => false,
  };
}

/// The fields of the create form, as typed: the basic form of the reference (#181) and its advanced options (#183).
///
/// The advanced options' values are kept while the options are closed, and sent: the reference does so (`buildOrderAttributes`, `MakerForm.tsx:257-275`, sends `public_duration`, `escrow_duration`, `bond_size` and `description` whatever `advancedOptions` says), only the range following the options ([hasRange]).
@immutable
final class MakerFormInput {
  /// « Buy » or « Sell », `null` until one is chosen; « Sell » is never chosen in this version.
  final OrderType? type;
  final RobosatsCurrency currency;
  final String amount;

  /// The names of the methods chosen, in the order they were chosen.
  final List<String> paymentMethods;
  final String premium;

  /// « Enable advanced options » (`maker.advancedOptions`, off by default, `models/Maker.model.ts:30`).
  final bool advanced;

  /// « Amount Range » rather than « Exact Amount » (`amountRangeEnabled`, on by default, `MakerForm.tsx:90`): a range only while [advanced] ([hasRange]).
  final bool rangeEnabled;

  /// « From » … « to » of the range, as typed.
  final String minAmount;
  final String maxAmount;

  /// « Description », as typed.
  final String description;

  /// « Public Duration (HH:mm) », « Escrow/Invoice Timer (HH:mm) » and « Fidelity Bond Size ».
  final Duration publicDuration;
  final Duration escrowDuration;
  final double bondSizePercent;

  MakerFormInput({
    required this.type,
    required this.currency,
    required this.amount,
    required Iterable<String> paymentMethods,
    required this.premium,
    this.advanced = false,
    this.rangeEnabled = true,
    this.minAmount = '',
    this.maxAmount = '',
    this.description = '',
    this.publicDuration = MakerFormCheck.publicDurationDefault,
    this.escrowDuration = MakerFormCheck.escrowDurationDefault,
    this.bondSizePercent = MakerFormCheck.bondSizeDefault,
  }) : paymentMethods = List.unmodifiable(paymentMethods);

  /// Whether the order is a range (`makerHasAmountRange`, `MakerForm.tsx:202-204`): the advanced options open and « Amount Range » chosen.
  bool get hasRange => advanced && rangeEnabled;
}

/// The bounds a range takes when the form sets them, as the reference's `resetRange` (`MakerForm.tsx:394-411`), its currency change (`:184-199`) and its slider (`AmountRange.tsx:79-117`) set them (#183).
@immutable
final class MakerRange {
  final double min;
  final double max;

  const MakerRange(this.min, this.max);

  /// The range « Enable advanced options » opens with (`resetRange`): half the amount typed and the amount, else a quarter and three quarters of the coordinator's largest order in the currency ([limit]'s `max_amount`, without the premium nor the form's margins, as the reference reads `limits[index].max_amount`), each to 2 significant digits but the amount typed, kept as it is; `null` when neither is known (no amount above zero, no limit for the currency), the fields then left as they are.
  static MakerRange? opening({
    required double? amount,
    required CurrencyLimit? limit,
  }) {
    if (amount != null && amount > 0) {
      return MakerRange(significant(amount / 2, 2), amount);
    }
    if (limit == null) return null;
    return _quarters(limit);
  }

  /// The range after a change of currency, the new currency's limit being [limit] (`handleCurrencyChange`, `:184-199`): kept when both bounds lie within its smallest and largest order (`min_amount` and `max_amount`, to 2 significant digits), else a quarter and three quarters of its largest order; `null` to keep it as typed (no limit for the currency, or a bound that is no number, which the reference cannot have).
  static MakerRange? afterCurrency({
    required double? min,
    required double? max,
    required CurrencyLimit? limit,
  }) {
    if (limit == null || min == null || max == null) return null;
    final low = significant(limit.minAmount, 2);
    final high = significant(limit.maxAmount, 2);
    if (min < low || min > high || max > high || max < low) {
      return _quarters(limit);
    }
    return null;
  }

  static MakerRange _quarters(CurrencyLimit limit) {
    final high = significant(limit.maxAmount, 2);
    return MakerRange(significant(high * 0.25, 2), significant(high * 0.75, 2));
  }

  /// The range the slider gives when one thumb moved to [next] from [previous] (`handleRangeAmountChange`, `AmountRange.tsx:79-117`): the minimum at most the form's largest amount × 0.98 / 1.6 and the maximum at least 1.6 × the form's smallest × 1.03 (`amountSafeThresholds` applied once more, as the reference writes it), then the other thumb moved so that the ratio stays from 1.6 to 14.8, then each bound to 2 significant digits below 100, 3 from 100.
  static MakerRange slid({
    required MakerRange previous,
    required MakerRange next,
    required MakerAmountLimits limits,
  }) {
    final minMoved = next.min != previous.min;
    var min = next.min;
    var max = next.max;
    final cap =
        limits.max *
        MakerAmountLimits.maxThreshold /
        MakerFormCheck.minRangeRatio;
    if (min > cap) min = cap;
    final floor =
        MakerFormCheck.minRangeRatio *
        limits.min *
        MakerAmountLimits.minThreshold;
    if (max < floor) max = floor;
    if (min > max / MakerFormCheck.minRangeRatio) {
      if (minMoved) {
        max = MakerFormCheck.minRangeRatio * min;
      } else {
        min = max / MakerFormCheck.minRangeRatio;
      }
    } else if (min < max / MakerFormCheck.maxRangeRatio) {
      if (minMoved) {
        max = MakerFormCheck.maxRangeRatio * min;
      } else {
        min = max / MakerFormCheck.maxRangeRatio;
      }
    }
    return MakerRange(_slidPrecision(min), _slidPrecision(max));
  }

  static double _slidPrecision(double value) =>
      significant(value, value < 100 ? 2 : 3);

  @override
  bool operator ==(Object other) =>
      other is MakerRange && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => 'MakerRange';
}

/// [value] to [digits] significant digits, as JavaScript's `parseFloat(Number(value).toPrecision(digits))`.
double significant(double value, int digits) =>
    double.parse(value.toStringAsPrecision(digits));

/// The create form judged by the reference's rules (`components/MakerForm/MakerForm.tsx`, `AmountRange.tsx`, commit ff1998c; design note `docs/design/phase-3-making-an-order.md` § 1.3, § 1.11, § 2.2), from what is typed and what the chosen coordinator gave: what each field says, the figures under the form, why « Create order » is disabled, or the request it sends.
///
/// The summary, the figures and the request are built from the same values ([amount] or the range's [rangeMin] and [rangeMax], [premiumPercent], [bondSizePercent]): nothing is sent that differs from what the summary shows.
@immutable
final class MakerFormCheck {
  /// The defaults of the advanced options (`models/Maker.model.ts:29-56`): public for 23:59, 3 hours for each step, a bond of 3 %.
  static const Duration publicDurationDefault = Duration(seconds: 86340);
  static const Duration escrowDurationDefault = Duration(seconds: 10800);
  static const double bondSizeDefault = 3;

  /// The bounds of « Public Duration (HH:mm) » (`minTime` 00:10, `maxTime` 23:59, `MakerForm.tsx:1144-1145`) and of « Escrow/Invoice Timer (HH:mm) » (01:00 to 10:00, `:1180-1181`), in whole minutes as the reference's picker gives them (`hours × 3600 + minutes × 60`, `:338-350`, `:367-379`).
  static const Duration minPublicDuration = Duration(minutes: 10);
  static const Duration maxPublicDuration = Duration(hours: 23, minutes: 59);
  static const Duration minEscrowDuration = Duration(hours: 1);
  static const Duration maxEscrowDuration = Duration(hours: 10);

  /// « Fidelity Bond Size » (`MakerForm.tsx:1232-1254`): 2 to 15 %, in steps of 0.25.
  static const double minBondSize = 2;
  static const double maxBondSize = 15;
  static const double bondSizeStep = 0.25;

  /// The ratios of a range's maximum to its minimum the form takes: the reference client's 1.6 and 14.8 (`maxRangeAmountMultiple`, `minRangeAmountMultiple`, `AmountRange.tsx:54-55`), so that a range the form takes is not refused by the coordinator, which compares sats at its price of the moment with its own 1.5 and 15 (`api/logics.py:157-175`; the package keeps those, `MakeOrderRequest.minRangeRatio`, design note § 2.2, #183's comment).
  static const double minRangeRatio = 1.6;
  static const double maxRangeRatio = 14.8;

  /// The longest « Description » (`MakerForm.tsx:363`), in UTF-16 units.
  static const int maxDescriptionLength = 240;

  /// The bounds of the premium field (`MakerForm.tsx:236-247`): above [maxPremium] or at [minPremium] and below, refused.
  static const double maxPremium = 999;
  static const double minPremium = -100;

  /// The premium the reference keeps in place of one out of bounds, for its figures (`:243`, `:246`).
  static const double lowestPremium = -99.99;

  /// The decimals each field keeps: the coordinator's (`MakeOrderRequest.amountDecimals`) for the amount and the range's bounds; 2 for the premium, the reference's rounding (`:238`).
  static const int amountDecimals = MakeOrderRequest.amountDecimals;
  static const int premiumDecimals = MakeOrderRequest.premiumDecimals;

  final FormNumber amountField;
  final FormNumber premiumField;

  /// Whether the order is a range ([MakerFormInput.hasRange]).
  final bool hasRange;

  /// The fixed amount the summary shows and the request sends: the number typed, 0 when nothing or no number is (the reference's `maker.amount ?? 0`).
  final double amount;

  /// « From » and « to » of a range, as read, and their values, `null` when no number is typed.
  final FormNumber minAmountField;
  final FormNumber maxAmountField;
  final double? rangeMin;
  final double? rangeMax;

  /// Whether the field « From », or « to », shows an error (`minAmountError`, `maxAmountError`, `AmountRange.tsx:57-77`); only for a range.
  final bool rangeMinError;
  final bool rangeMaxError;

  /// The premium of the summary and of the figures: the number typed, 0 when empty or no number, kept within its bounds as the reference keeps it (999, or −99.99).
  final double premiumPercent;

  final MakerAmountProblem? amountProblem;
  final MakerPremiumProblem? premiumProblem;

  /// The methods' text, joined by spaces as the reference joins them (`:206-232`), and whether it is too long.
  final String paymentMethodText;
  final bool badPaymentMethod;

  /// The description sent ([OrderDescription.keptOf]), `null` for none, and what its field says: too long, or not seen as written.
  final String? description;
  final bool descriptionTooLong;
  final bool descriptionNotShown;

  /// The durations and the bond size sent.
  final Duration publicDuration;
  final Duration escrowDuration;
  final double bondSizePercent;

  /// The coordinator's price of a bitcoin in the currency (`/api/limits/`), when it gave a usable one.
  final double? price;

  /// The form's amount limits at that price ([MakerAmountLimits], the make use case's own), when there is one.
  final MakerAmountLimits? limits;

  /// « Order current rate: »: the price with the premium, to 5 significant digits (`:160-169`).
  final double? rate;

  /// « Estimated Bond: … Sats » (`:618-622`, `utils/bondCalculator.ts:12-41`): the amount, the maximum of a range (`isRange ? maxAmount : amount`), over [rate], in sats, times the bond size, rounded down; only for an amount above zero.
  final int? estimatedBond;

  /// Why « Create order » is disabled, or `null` when [request] is ready.
  final MakerFormBlock? block;

  /// The request « Create order » sends, built from the values the summary shows; `null` when [block] is set.
  final MakeOrderRequest? request;

  const MakerFormCheck._({
    required this.amountField,
    required this.premiumField,
    required this.hasRange,
    required this.amount,
    required this.minAmountField,
    required this.maxAmountField,
    required this.rangeMin,
    required this.rangeMax,
    required this.rangeMinError,
    required this.rangeMaxError,
    required this.premiumPercent,
    required this.amountProblem,
    required this.premiumProblem,
    required this.paymentMethodText,
    required this.badPaymentMethod,
    required this.description,
    required this.descriptionTooLong,
    required this.descriptionNotShown,
    required this.publicDuration,
    required this.escrowDuration,
    required this.bondSizePercent,
    required this.price,
    required this.limits,
    required this.rate,
    required this.estimatedBond,
    required this.block,
    required this.request,
  });

  /// [duration] as the picker of « Public Duration (HH:mm) » gives it: whole minutes, within [minPublicDuration] and [maxPublicDuration] (a time outside them is moved to the nearest bound, where the reference's picker greys it out).
  static Duration publicDurationOf(Duration duration) =>
      _minutesWithin(duration, minPublicDuration, maxPublicDuration);

  /// [duration] as the picker of « Escrow/Invoice Timer (HH:mm) » gives it: whole minutes, within [minEscrowDuration] and [maxEscrowDuration].
  static Duration escrowDurationOf(Duration duration) =>
      _minutesWithin(duration, minEscrowDuration, maxEscrowDuration);

  static Duration _minutesWithin(
    Duration duration,
    Duration min,
    Duration max,
  ) {
    final minutes = Duration(minutes: duration.inMinutes);
    if (minutes < min) return min;
    if (minutes > max) return max;
    return minutes;
  }

  /// [percent] as the slider of « Fidelity Bond Size » gives it: a step of [bondSizeStep] within [minBondSize] and [maxBondSize].
  static double bondSizeOf(double percent) {
    if (!percent.isFinite) return bondSizeDefault;
    final steps = ((percent - minBondSize) / bondSizeStep).round();
    final value = minBondSize + steps * bondSizeStep;
    if (value < minBondSize) return minBondSize;
    if (value > maxBondSize) return maxBondSize;
    return value;
  }

  /// Whether [high] is from [minRangeRatio] to [maxRangeRatio] times [low], both at least as large as each bound, compared on the decimals the fields show ([ExactRatio]), so that 200 and 320 are exactly 1.6 and allowed, where floating point could put either bound one ulp off.
  static bool _ratioWithin(double low, double high) {
    final min = ExactRatio.ofDouble(low);
    final max = ExactRatio.ofDouble(high);
    final lowest = ExactRatio.ofDouble(minRangeRatio);
    final highest = ExactRatio.ofDouble(maxRangeRatio);
    if (min == null || max == null || lowest == null || highest == null) {
      return false;
    }
    final ratio = max / min;
    return ratio >= lowest && ratio <= highest;
  }

  static bool _isDuration(Duration duration, Duration min, Duration max) =>
      duration.inMicroseconds % Duration.microsecondsPerMinute == 0 &&
      duration >= min &&
      duration <= max;

  static bool _isBondSize(double percent) =>
      percent.isFinite &&
      percent >= minBondSize &&
      percent <= maxBondSize &&
      ((percent - minBondSize) / bondSizeStep) ==
          ((percent - minBondSize) / bondSizeStep).roundToDouble();

  /// The form [input] judged with the coordinator's [market] limits, its size limit [sizeLimitSats] (`CoordinatorSizeLimit`), and whether the default coordinator is drawn ([coordinatorsLoaded]).
  factory MakerFormCheck.of(
    MakerFormInput input, {
    required bool coordinatorsLoaded,
    required MakerFormLimits market,
    required double sizeLimitSats,
  }) {
    final hasRange = input.hasRange;
    final amountField = FormNumber.read(
      input.amount,
      maxDecimals: amountDecimals,
    );
    final minAmountField = FormNumber.read(
      input.minAmount,
      maxDecimals: amountDecimals,
    );
    final maxAmountField = FormNumber.read(
      input.maxAmount,
      maxDecimals: amountDecimals,
    );
    final premiumField = FormNumber.read(
      input.premium,
      maxDecimals: premiumDecimals,
    );
    final amount = amountField.value ?? 0.0;
    final rangeMin = minAmountField.value;
    final rangeMax = maxAmountField.value;
    final typedPremium = premiumField.value ?? 0.0;
    final premiumProblem = typedPremium > maxPremium
        ? MakerPremiumProblem.tooHigh
        : typedPremium <= minPremium
        ? MakerPremiumProblem.tooLow
        : null;
    final premiumPercent = switch (premiumProblem) {
      MakerPremiumProblem.tooHigh => maxPremium,
      MakerPremiumProblem.tooLow => lowestPremium,
      null => typedPremium,
    };
    final paymentMethodText = input.paymentMethods.join(' ');
    final badPaymentMethod =
        paymentMethodText.length > CustomPaymentMethod.maxLength;
    final description = OrderDescription.keptOf(input.description);
    final descriptionTooLong = OrderDescription.tooLong(input.description);
    final descriptionNotShown = OrderDescription.notShownAsWritten(
      input.description,
    );
    final bondSizePercent = input.bondSizePercent;

    final limit = switch (market) {
      MakerFormLimitsRead(:final limits) => limits[input.currency],
      _ => null,
    };
    // A price the make's terms would refuse (`MakerTerms.create`) gives no figure: every one shown is then finite.
    final price =
        limit != null &&
            limit.price >= MakerTerms.minCreatedPrice &&
            limit.price < MakerTerms.maxCreatedPrice
        ? limit.price
        : null;
    final premium = Premium.tryCreate(premiumPercent);
    final MakerAmountLimits? limits = limit != null && price != null
        ? switch (premium) {
            final premium? => MakerAmountLimits.of(
              limit,
              premium: premium,
              sizeLimitSats: sizeLimitSats,
            ),
            null => null,
          }
        : null;
    final rate = price == null
        ? null
        : significant(price * (1 + premiumPercent / 100), 5);
    // The reference's estimate is on the range's maximum (`bondCalculator.ts:24`), the bond the coordinator asks (`api/logics.py:1266-1268`).
    final estimatedAmount = hasRange ? (rangeMax ?? 0.0) : amount;
    final estimatedBond = rate != null && rate > 0 && estimatedAmount > 0
        ? _bondOf(estimatedAmount, rate, bondSizePercent)
        : null;
    final amountProblem = hasRange || limits == null || amount == 0
        ? null
        : amount < limits.min
        ? MakerAmountTooLow(significant(limits.min, 2))
        : amount > limits.max
        ? MakerAmountTooHigh(significant(limits.max, 2))
        : null;

    // The range's own checks (`AmountRange.tsx:57-77`): a bound below 0.99 of the form's smallest amount or above 1.01 of its largest, a maximum below the minimum, or a ratio outside the form's (the reference's typed check lets 1.5 to 14.95 through, its slider 1.6 to 14.8: here 1.6 to 14.8 for both, see [minRangeRatio]). A bound with no number is an error of its own field, where the reference's number field reads an empty one as 0.
    var rangeMinError = false;
    var rangeMaxError = false;
    if (hasRange) {
      final low = rangeMin;
      final high = rangeMax;
      if (low == null || low <= 0) rangeMinError = true;
      if (high == null || high <= 0) rangeMaxError = true;
      if (low != null && high != null && low > 0 && high > 0) {
        if (!_ratioWithin(low, high)) {
          rangeMinError = true;
          rangeMaxError = true;
        }
      }
      if (limits != null) {
        if (low != null &&
            low < limits.min * MakerAmountLimits.rangeMinMargin) {
          rangeMinError = true;
        }
        if (high != null &&
            high > limits.max * MakerAmountLimits.rangeMaxMargin) {
          rangeMaxError = true;
        }
      }
    }

    MakerFormCheck build(MakerFormBlock? block, MakeOrderRequest? request) =>
        MakerFormCheck._(
          amountField: amountField,
          premiumField: premiumField,
          hasRange: hasRange,
          amount: amount,
          minAmountField: minAmountField,
          maxAmountField: maxAmountField,
          rangeMin: rangeMin,
          rangeMax: rangeMax,
          rangeMinError: rangeMinError,
          rangeMaxError: rangeMaxError,
          premiumPercent: premiumPercent,
          amountProblem: amountProblem,
          premiumProblem: premiumProblem,
          paymentMethodText: paymentMethodText,
          badPaymentMethod: badPaymentMethod,
          description: description,
          descriptionTooLong: descriptionTooLong,
          descriptionNotShown: descriptionNotShown,
          publicDuration: input.publicDuration,
          escrowDuration: input.escrowDuration,
          bondSizePercent: bondSizePercent,
          price: price,
          limits: limits,
          rate: rate,
          estimatedBond: estimatedBond,
          block: block,
          request: request,
        );
    MakerFormCheck blocked(MakerFormBlock block) => build(block, null);

    if (!coordinatorsLoaded) return blocked(MakerFormBlock.loadingCoordinators);
    if (market is MakerFormLimitsUnreadable) {
      return blocked(MakerFormBlock.limitsUnavailable);
    }
    if (limits == null || rate == null) {
      return blocked(MakerFormBlock.priceNotSynchronized);
    }
    final type = input.type;
    if (type == null) return blocked(MakerFormBlock.noSide);
    if (type != OrderType.buy) return blocked(MakerFormBlock.sellComingLater);
    if (amountProblem != null) {
      return blocked(MakerFormBlock.amountOutsideLimits);
    }
    if (badPaymentMethod) return blocked(MakerFormBlock.badPaymentMethod);
    if (!hasRange && amountField is! FormNumberValue) {
      return blocked(MakerFormBlock.noAmount);
    }
    if (hasRange && (rangeMinError || rangeMaxError)) {
      return blocked(MakerFormBlock.amountRangeInvalid);
    }
    if (!hasRange && amount <= 0) {
      return blocked(MakerFormBlock.amountNotPositive);
    }
    if (premiumProblem != null) return blocked(MakerFormBlock.premiumInvalid);
    if (premiumField is FormNumberInvalid) {
      return blocked(MakerFormBlock.premiumNotANumber);
    }
    if (input.paymentMethods.isEmpty) {
      return blocked(MakerFormBlock.noPaymentMethod);
    }
    if (descriptionTooLong || descriptionNotShown) {
      return blocked(MakerFormBlock.descriptionInvalid);
    }
    final OrderAmount? orderAmount;
    if (hasRange) {
      final low = rangeMin == null ? null : FiatAmount.tryCreate(rangeMin);
      final high = rangeMax == null ? null : FiatAmount.tryCreate(rangeMax);
      orderAmount = low == null || high == null
          ? null
          : RangeOrderAmount.tryCreate(low, high);
    } else {
      final fiat = FiatAmount.tryCreate(amount);
      orderAmount = fiat == null ? null : FixedOrderAmount(fiat);
    }
    final bondSize = _isBondSize(bondSizePercent)
        ? BondSize.tryCreate(bondSizePercent)
        : null;
    final durationsValid =
        _isDuration(
          input.publicDuration,
          minPublicDuration,
          maxPublicDuration,
        ) &&
        _isDuration(input.escrowDuration, minEscrowDuration, maxEscrowDuration);
    final request =
        orderAmount == null ||
            premium == null ||
            bondSize == null ||
            !durationsValid
        ? null
        : MakeOrderRequest.tryCreate(
            type: type,
            currency: input.currency,
            amount: orderAmount,
            paymentMethod: paymentMethodText,
            premium: premium,
            publicDuration: input.publicDuration,
            escrowDuration: input.escrowDuration,
            bondSize: bondSize,
            description: description,
          );
    // The use case refuses an amount outside these very limits before any robot; the form never offers one.
    if (request == null || !limits.allows(request.amount)) {
      return blocked(MakerFormBlock.formIncorrect);
    }
    return build(null, request);
  }

  /// The reference's estimate (`calculateBondAmount`, `utils/bondCalculator.ts:12-41`): `Math.floor((amount / price) * 100_000_000 * (bondSize / 100))`, in that order and in floating point, at the rounded rate, so that the figure is the reference's own; `null` when it is no figure.
  ///
  /// The coordinator computes the bond at its unrounded rate (`Logics.calc_sats`, `api/logics.py:256-259`), as `MakerTerms.expectedBond` does: the two differ by the rate's rounding to 5 significant digits only, at most about 0.005 % of the bond (design note § 6, issue #181).
  static int? _bondOf(double amount, double rate, double bondSizePercent) {
    final bond = (amount / rate) * 100000000 * (bondSizePercent / 100);
    if (!bond.isFinite || bond < 0 || bond >= 9e15) return null;
    return bond.floor();
  }
}
