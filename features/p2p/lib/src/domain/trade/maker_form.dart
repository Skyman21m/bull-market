import 'package:meta/meta.dart';
import 'package:robosats/robosats.dart';

import 'maker_terms.dart';
import 'trade_make.dart';

/// A number typed in a field of the create form (#181): the text read once, by one rule, so that what the summary shows and what the request sends are the same value.
///
/// The reference reads its fields as `type='number'` inputs (`components/MakerForm/MakerForm.tsx:875-901`, `:1030-1049`, commit ff1998c), which the browser keeps to a plain decimal number; here the text is read as such a number and nothing else:
/// - spaces at either end are ignored; a space, a letter or a sign `+` inside makes it no number;
/// - a comma is read as the decimal separator as well as a point, as the take's amount field reads it (`TakeAmountInput`), and only one separator is allowed, so `1,000.5` and `1.000,5` are no numbers rather than guesses;
/// - the digits of the Arabic-Indic, the Extended Arabic-Indic (Persian) and the Devanagari scripts, and the full-width digits, are read as their values, the Arabic decimal separator (U+066B) and the full-width full stop (U+FF0E) as a point, the full-width comma (U+FF0C) as a comma; any other character is no number;
/// - `NaN`, `Infinity`, an exponent, a hexadecimal number, a figure that is not finite once read, more than [maxLength] characters or more decimals than the field keeps are no number;
/// - a minus sign is read (a negative premium is a discount); `-0` is 0.
@immutable
sealed class FormNumber {
  const FormNumber();

  /// The most characters a field takes, as the take's amount field (`LengthLimitingTextInputFormatter(20)`).
  static const int maxLength = 20;

  /// What [text] says, with at most [maxDecimals] decimals.
  static FormNumber read(String text, {required int maxDecimals}) {
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
    return FormNumberValue(value == 0 ? 0.0 : value);
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
/// The reference's reasons of the advanced options (« The amount range is not valid. », « The description is not valid. ») and of its legacy mode cannot apply to this form and are left out; [sellComingLater] is the app's own.
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

  /// « Please enter an amount. »: nothing typed, or no number.
  noAmount,

  /// « The amount must be greater than 0. »
  amountNotPositive,

  /// « The premium is not valid. »: above 999 % or at most −100 %.
  premiumInvalid,

  /// « The premium must be a number. »: something typed that is no number (an empty premium is 0, « at market price »).
  premiumNotANumber,

  /// « Please select a payment method. »
  noPaymentMethod,

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

/// The fields of the create form, as typed (#181): the basic form of the reference, its advanced options left at their defaults.
@immutable
final class MakerFormInput {
  /// « Buy » or « Sell », `null` until one is chosen; « Sell » is never chosen in this version.
  final OrderType? type;
  final RobosatsCurrency currency;
  final String amount;

  /// The names of the methods chosen, in the order they were chosen.
  final List<String> paymentMethods;
  final String premium;

  MakerFormInput({
    required this.type,
    required this.currency,
    required this.amount,
    required Iterable<String> paymentMethods,
    required this.premium,
  }) : paymentMethods = List.unmodifiable(paymentMethods);
}

/// The create form judged by the reference's rules (`components/MakerForm/MakerForm.tsx`, commit ff1998c; design note `docs/design/phase-3-making-an-order.md` § 1.3, § 1.11), from what is typed and what the chosen coordinator gave: what each field says, the figures under the form, why « Create order » is disabled, or the request it sends.
///
/// The summary, the figures and the request are built from the same values ([amount], [premiumPercent]): nothing is sent that differs from what the summary shows.
@immutable
final class MakerFormCheck {
  /// The defaults of the advanced options, which this version does not open (`models/Maker.model.ts:29-56`): public for 23:59, 3 hours for each step, a bond of 3 %.
  static const Duration publicDuration = Duration(seconds: 86340);
  static const Duration escrowDuration = Duration(seconds: 10800);
  static const double bondSizePercent = 3;

  /// The bounds of the premium field (`MakerForm.tsx:236-247`): above [maxPremium] or at [minPremium] and below, refused.
  static const double maxPremium = 999;
  static const double minPremium = -100;

  /// The premium the reference keeps in place of one out of bounds, for its figures (`:243`, `:246`).
  static const double lowestPremium = -99.99;

  /// The decimals each field keeps: the coordinator's (`MakeOrderRequest.amountDecimals`) for the amount; 2 for the premium, the reference's rounding (`:238`).
  static const int amountDecimals = MakeOrderRequest.amountDecimals;
  static const int premiumDecimals = MakeOrderRequest.premiumDecimals;

  final FormNumber amountField;
  final FormNumber premiumField;

  /// The amount the summary shows and the request sends: the number typed, 0 when nothing or no number is (the reference's `maker.amount ?? 0`).
  final double amount;

  /// The premium of the summary and of the figures: the number typed, 0 when empty or no number, kept within its bounds as the reference keeps it (999, or −99.99).
  final double premiumPercent;

  final MakerAmountProblem? amountProblem;
  final MakerPremiumProblem? premiumProblem;

  /// The methods' text, joined by spaces as the reference joins them (`:206-232`), and whether it is too long.
  final String paymentMethodText;
  final bool badPaymentMethod;

  /// The coordinator's price of a bitcoin in the currency (`/api/limits/`), when it gave a usable one.
  final double? price;

  /// The form's amount limits at that price ([MakerAmountLimits], the make use case's own), when there is one.
  final MakerAmountLimits? limits;

  /// « Order current rate: »: the price with the premium, to 5 significant digits (`:160-169`).
  final double? rate;

  /// « Estimated Bond: … Sats » (`:618-622`, `utils/bondCalculator.ts:12-41`): the amount over [rate], in sats, times the bond size, rounded down; only for an amount above zero.
  final int? estimatedBond;

  /// Why « Create order » is disabled, or `null` when [request] is ready.
  final MakerFormBlock? block;

  /// The request « Create order » sends, built from [amount] and [premiumPercent]; `null` when [block] is set.
  final MakeOrderRequest? request;

  const MakerFormCheck._({
    required this.amountField,
    required this.premiumField,
    required this.amount,
    required this.premiumPercent,
    required this.amountProblem,
    required this.premiumProblem,
    required this.paymentMethodText,
    required this.badPaymentMethod,
    required this.price,
    required this.limits,
    required this.rate,
    required this.estimatedBond,
    required this.block,
    required this.request,
  });

  /// The form [input] judged with the coordinator's [market] limits, its size limit [sizeLimitSats] (`CoordinatorSizeLimit`), and whether the default coordinator is drawn ([coordinatorsLoaded]).
  factory MakerFormCheck.of(
    MakerFormInput input, {
    required bool coordinatorsLoaded,
    required MakerFormLimits market,
    required double sizeLimitSats,
  }) {
    final amountField = FormNumber.read(
      input.amount,
      maxDecimals: amountDecimals,
    );
    final premiumField = FormNumber.read(
      input.premium,
      maxDecimals: premiumDecimals,
    );
    final amount = amountField.value ?? 0.0;
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
        : _significant(price * (1 + premiumPercent / 100), 5);
    final estimatedBond = rate != null && rate > 0 && amount > 0
        ? _bondOf(amount, rate)
        : null;
    final amountProblem = limits == null || amount == 0
        ? null
        : amount < limits.min
        ? MakerAmountTooLow(_significant(limits.min, 2))
        : amount > limits.max
        ? MakerAmountTooHigh(_significant(limits.max, 2))
        : null;

    MakerFormCheck blocked(MakerFormBlock block) => MakerFormCheck._(
      amountField: amountField,
      premiumField: premiumField,
      amount: amount,
      premiumPercent: premiumPercent,
      amountProblem: amountProblem,
      premiumProblem: premiumProblem,
      paymentMethodText: paymentMethodText,
      badPaymentMethod: badPaymentMethod,
      price: price,
      limits: limits,
      rate: rate,
      estimatedBond: estimatedBond,
      block: block,
      request: null,
    );

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
    if (amountField is! FormNumberValue) {
      return blocked(MakerFormBlock.noAmount);
    }
    if (amount <= 0) return blocked(MakerFormBlock.amountNotPositive);
    if (premiumProblem != null) return blocked(MakerFormBlock.premiumInvalid);
    if (premiumField is FormNumberInvalid) {
      return blocked(MakerFormBlock.premiumNotANumber);
    }
    if (input.paymentMethods.isEmpty) {
      return blocked(MakerFormBlock.noPaymentMethod);
    }
    final fiat = FiatAmount.tryCreate(amount);
    final bondSize = BondSize.tryCreate(bondSizePercent);
    final request = fiat == null || premium == null || bondSize == null
        ? null
        : MakeOrderRequest.tryCreate(
            type: type,
            currency: input.currency,
            amount: FixedOrderAmount(fiat),
            paymentMethod: paymentMethodText,
            premium: premium,
            publicDuration: publicDuration,
            escrowDuration: escrowDuration,
            bondSize: bondSize,
          );
    // The use case refuses an amount outside these very limits before any robot; the form never offers one.
    if (request == null || !limits.allows(request.amount)) {
      return blocked(MakerFormBlock.formIncorrect);
    }
    return MakerFormCheck._(
      amountField: amountField,
      premiumField: premiumField,
      amount: amount,
      premiumPercent: premiumPercent,
      amountProblem: null,
      premiumProblem: null,
      paymentMethodText: paymentMethodText,
      badPaymentMethod: false,
      price: price,
      limits: limits,
      rate: rate,
      estimatedBond: estimatedBond,
      block: null,
      request: request,
    );
  }

  /// [value] to [digits] significant digits, as JavaScript's `parseFloat(Number(value).toPrecision(digits))`.
  static double _significant(double value, int digits) =>
      double.parse(value.toStringAsPrecision(digits));

  /// The reference's estimate (`calculateBondAmount`, `utils/bondCalculator.ts:12-41`): `Math.floor((amount / price) * 100_000_000 * (bondSize / 100))`, in that order and in floating point, at the rounded rate, so that the figure is the reference's own; `null` when it is no figure.
  ///
  /// The coordinator computes the bond at its unrounded rate (`Logics.calc_sats`, `api/logics.py:256-259`), as `MakerTerms.expectedBond` does: the two differ by the rate's rounding to 5 significant digits only, at most about 0.005 % of the bond (design note § 6, issue #181).
  static int? _bondOf(double amount, double rate) {
    final bond = (amount / rate) * 100000000 * (bondSizePercent / 100);
    if (!bond.isFinite || bond < 0 || bond >= 9e15) return null;
    return bond.floor();
  }
}
