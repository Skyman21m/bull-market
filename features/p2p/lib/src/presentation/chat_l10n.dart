import 'package:flutter/widgets.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/trade/trade_chat.dart';

/// Why a message was not sent (#93), in words of the reference or of the app: never the text typed, never a coordinator's text.
extension ChatSendRefusalL10n on ChatSendRefusal {
  /// The text, naming [coordinator], the long alias of the trade's coordinator.
  String toText(BuildContext context, {required String coordinator}) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      // « Send » is off for an empty text: never shown.
      ChatTextEmpty() => l10n.p2pChatTypeMessage,
      ChatTextTooLong() => l10n.p2pChatTooLong,
      ChatTextHoldsToken() => l10n.p2pChatTokenBlocked,
      ChatTextHoldsGarageKey() => l10n.p2pChatGarageKeyBlocked,
      ChatTextIsPayout() => l10n.p2pChatPayoutBlocked,
      ChatPeerKeyNotKnown() => l10n.p2pChatWaitingForPeer,
      ChatPeerKeyChanged() => l10n.p2pChatKeyChanged,
      ChatClosed() => l10n.p2pChatClosed,
      ChatSendUnavailable() => l10n.p2pChatSendFailed,
      ChatSendRefused(fromLastRead: true) => l10n.p2pChatTradeMoved,
      ChatSendRefused(cause: CoordinatorTransportBusy()) => l10n.p2pRobotBusy,
      ChatSendRefused() => l10n.p2pChatSendRefused(coordinator),
    };
  }
}

/// Why the last read of the chat gave nothing new (#93), or `null` when the panel says nothing of it.
extension ChatReadFailureL10n on ChatReadFailure {
  String? toText(BuildContext context, {required String coordinator}) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      // Nothing was asked: the status shown is not one of the chat.
      ChatNotOpen() => null,
      ChatTradeUnavailable() => l10n.p2pChatUnavailable,
      ChatReadFailed(cause: CoordinatorTransportBusy()) => l10n.p2pRobotBusy,
      ChatReadFailed() => l10n.p2pChatReadFailed(coordinator),
    };
  }
}
