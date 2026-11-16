import 'package:primitives/primitives.dart';

/// No token to rate the trade's coordinator (« Rate your host », #95): the coordinator refused it (1052), answered something else, or could not be asked (Tor, a busy coordinator, a trade that could not be opened, a status that does not offer the rating).
///
/// Without a token nothing is published, as in the reference (`rateHostPlatform`, `TradeBox/Prompts/Successful.tsx:58-61`, commit ff1998c), and nothing asks for it again until the trade's screen is opened again.
final class HostTokenNotGiven extends Failure {
  const HostTokenNotGiven();
}
