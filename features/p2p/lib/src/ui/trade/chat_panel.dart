import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:screen_privacy/screen_privacy.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade/trade_chat.dart';
import '../../domain/trade/trade_watch.dart';
import '../../domain/trade_record.dart';
import '../../presentation/chat_cubit.dart';
import '../../presentation/chat_l10n.dart';
import '../widgets/robot_avatar.dart';
import '../widgets/trade_button.dart';

/// What the trade screen gives the chat panel of the status it shows.
@immutable
final class ChatPanelRequest {
  final TradeRecord record;

  /// The status shown, with the order it was read from.
  final TradeSeen seen;

  /// The long alias of the trade's coordinator, for the texts.
  final String coordinator;

  const ChatPanelRequest({
    required this.record,
    required this.seen,
    required this.coordinator,
  });
}

/// Builds the chat panel of [request]: the route gives it, with the panel's cubit.
typedef ChatPanelBuilder =
    Widget Function(BuildContext context, ChatPanelRequest request);

/// The official client's encrypted chat (`TradeBox/EncryptedChat/EncryptedApiChat/index.tsx`, `ChatHeader/index.tsx`, `MessageCard/index.tsx`, commit ff1998c) in the wallet's look (#93): « You: connected », « Peer: … », the messages with the author's tick or cross and its tooltip and a copy of each, the field « Type a message » and « Send », disabled while the peer's key is not known (« Waiting for peer... »).
///
/// Every message holds the parties' payment details: the panel is protected from screen capture as the Garage is (`PrivacyScreen`, design note § 4.3), and draws nothing until the protection says it is on.
/// While shown with the app in the foreground and its tab of the shell visible, its cubit reads the chat every 5 s and holds the robot's key; otherwise neither.
/// What the chat says beyond the reference (a message not confirmed, shown again, after a gap, a key that changed, a send refused, each wait) is in words of the app, declared in `AGENTS.md`.
class ChatPanel extends StatefulWidget {
  final ChatPanelRequest request;

  const ChatPanel({super.key, required this.request});

  /// The key of the field, for the tests.
  static const field = ValueKey('chat-field');

  /// The height of the messages, the reference's 18.42 em at its 14 px.
  static const messagesHeight = 258.0;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel>
    with PrivacyScreen, WidgetsBindingObserver {
  late Future<bool> _protection = _protect();

  /// Whether the screen's protection is on: the chat is read and the key held only then (review of #93).
  bool _protected = false;
  final _text = TextEditingController();
  final _scroll = ScrollController();
  late final ChatCubit _cubit;
  bool _foreground = true;
  bool _tickerEnabled = true;
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cubit = context.read<ChatCubit>()..show(widget.request.seen);
    _text.text = _cubit.state.text;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground =
        lifecycle == null ||
        lifecycle == AppLifecycleState.resumed ||
        lifecycle == AppLifecycleState.inactive;
  }

  @override
  void didUpdateWidget(ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.request.seen, widget.request.seen)) {
      _cubit.show(widget.request.seen);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _keepActive();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _foreground = false;
      case AppLifecycleState.resumed:
        _foreground = true;
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        return;
    }
    _keepActive();
  }

  /// Turns the protection on, and the reads with it once it is.
  Future<bool> _protect() async {
    final on = await enableScreenPrivacy();
    if (mounted) {
      _protected = on;
      _keepActive();
    }
    return on;
  }

  /// Reads and holds the key while protected, shown in the foreground with its tab visible; neither otherwise.
  void _keepActive() {
    if (_protected && _foreground && _tickerEnabled) {
      _cubit.activate();
    } else {
      _cubit.deactivate();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cubit.deactivate();
    unawaited(disableScreenPrivacy());
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The field made the cubit's text: after a send it empties.
  void _sync(ChatPanelState state) {
    if (_text.text == state.text) return;
    _text.value = TextEditingValue(
      text: state.text,
      selection: TextSelection.collapsed(offset: state.text.length),
    );
  }

  /// A new message brings the list to its end, as the reference scrolls it into view.
  void _follow(ChatPanelState state) {
    final count = state.view.entries.length + state.view.pending.length;
    if (count <= _shown) return;
    _shown = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return FutureBuilder<bool>(
      future: _protection,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        if (snapshot.data != true) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Line(
                l10n.p2pChatScreenPrivacyUnavailable,
                color: context.bull.error,
                center: true,
              ),
              const Gap(BullSpacing.sm),
              TradeButton(
                label: l10n.p2pCommonRetry,
                outlined: true,
                onPressed: () => setState(() {
                  _protection = _protect();
                }),
              ),
            ],
          );
        }
        return BlocConsumer<ChatCubit, ChatPanelState>(
          listener: (context, state) {
            _sync(state);
            _follow(state);
          },
          builder: (context, state) => _chat(context, state),
        );
      },
    );
  }

  Widget _chat(BuildContext context, ChatPanelState state) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final view = state.view;
    final coordinator = widget.request.coordinator;
    final order = widget.request.seen.order;
    final takerNick = order?.taker?.nickname;
    final ownNick = order == null
        ? null
        : order.isMaker
        ? order.maker.nickname
        : order.taker?.nickname;
    // The robot's face, seeded as the Garage and the order seed it, by its hash id (`MessageCard/index.tsx:181`).
    String faceOf(String nick) => switch (order) {
      final order? when nick == takerNick => order.taker?.hex ?? nick,
      final order? => order.maker.hex,
      null => nick,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(view: view),
        const Gap(BullSpacing.xs),
        // The first read (Tor, and the robot's key for the messages), until one succeeds or fails.
        if (!view.connected && state.readFailure == null)
          _Line(
            l10n.p2pChatReading(coordinator),
            color: colors.textMuted,
            small: true,
            live: true,
          ),
        if (view.historyTooLarge) ...[
          _Line(l10n.p2pChatHistoryTooLarge, color: colors.warning),
          if (state.skipAwaited)
            _Line(
              l10n.p2pChatSkipAwaited,
              color: colors.textMuted,
              small: true,
              live: true,
            )
          else
            TextButton(
              onPressed: _cubit.readNewerOnly,
              child: Text(
                l10n.p2pChatReadNewer,
                style: TextStyle(color: colors.primary),
              ),
            ),
        ],
        if (view.skippedEarlier)
          _Line(
            l10n.p2pChatEarlierHidden,
            color: colors.textMuted,
            small: true,
          ),
        Container(
          height: ChatPanel.messagesHeight,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(BullRadius.xxs),
          ),
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(BullSpacing.xs),
            children: [
              for (final entry in view.entries)
                _MessageCard(
                  entry: entry,
                  face: faceOf(entry.nick),
                  isTaker: entry.nick == takerNick,
                  connected:
                      entry.author == ChatAuthor.self || view.peerConnected,
                ),
              for (final pending in view.pending)
                _PendingCard(
                  pending: pending,
                  nick: ownNick ?? '',
                  face: faceOf(ownNick ?? ''),
                  isTaker: ownNick != null && ownNick == takerNick,
                  coordinator: coordinator,
                  sending: state.sending == pending.id,
                  onSendAgain: state.sending == null && view.canSend
                      ? () => unawaited(_cubit.sendAgain(pending.id))
                      : null,
                ),
            ],
          ),
        ),
        const Gap(BullSpacing.sm),
        ..._keyLines(context, view, coordinator),
        _fieldAndSend(context, state),
        // The wait of a send, or of a message sent again.
        if (state.sending != null)
          _Line(
            l10n.p2pChatSending(coordinator),
            color: colors.textMuted,
            small: true,
            live: true,
          ),
        if (state.refusal case final refusal?)
          _Line(
            refusal.toText(context, coordinator: coordinator),
            color: colors.error,
            small: true,
            live: true,
          ),
        if (state.readFailure?.toText(context, coordinator: coordinator)
            case final failure?)
          _Line(failure, color: colors.textMuted, small: true),
      ],
    );
  }

  /// The field and « Send » side by side, as the reference lays them out; the button under the field when the text is large, so that the field keeps its width on a phone of 320 points.
  Widget _fieldAndSend(BuildContext context, ChatPanelState state) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final view = state.view;
    // The reference's label of the field (`label={t('Type a message')}`), above it so that it wraps at a large text size.
    final field = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Text(
            l10n.p2pChatTypeMessage,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: colors.textMuted),
          ),
        ),
        const Gap(BullSpacing.xxs),
        Semantics(
          label: l10n.p2pChatTypeMessage,
          child: BullInputText(
            uiKey: ChatPanel.field,
            controller: _text,
            value: state.text,
            onChanged: _cubit.edit,
            minLines: 1,
            maxLines: 3,
          ),
        ),
      ],
    );
    final send = Tooltip(
      // The reference's tooltip while the peer's key is not known; after a breach, why nothing is sent.
      message: switch (view.peerKey) {
        ChatPeerKeyAwaited() => l10n.p2pChatWaitingForPeer,
        ChatPeerKeyBreach() => l10n.p2pChatKeyChanged,
        ChatPeerKeyPinned() => l10n.p2pChatSend,
      },
      child: IconButton.filled(
        onPressed: state.canSend ? () => unawaited(_cubit.send()) : null,
        style: IconButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
        ),
        icon: state.sending == 0
            ? SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.onPrimary,
                ),
              )
            : const Icon(Icons.send),
      ),
    );
    if (MediaQuery.textScalerOf(context).scale(1) >= 1.5) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field,
          const Gap(BullSpacing.xs),
          Align(alignment: AlignmentDirectional.centerEnd, child: send),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: field),
        const Gap(BullSpacing.xs),
        send,
      ],
    );
  }

  List<Widget> _keyLines(
    BuildContext context,
    ChatView view,
    String coordinator,
  ) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    // One wording for a key that changed and one that is not the peer's: what it means and what to do. A pointer to « Open Dispute » goes here once the chat step's options dialog exists (#95).
    return switch (view.peerKey) {
      ChatPeerKeyBreach() => [
        _Line(l10n.p2pChatKeyChanged, color: colors.error, live: true),
        const Gap(BullSpacing.xs),
      ],
      _ => const [],
    };
  }
}

/// « You: connected / disconnected » and « Peer: connected / disconnected / ...waiting » (`ChatHeader/index.tsx`).
class _Header extends StatelessWidget {
  final ChatView view;

  const _Header({required this.view});

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    // The reference's « connected » is a peer's key received (`EncryptedApiChat/index.tsx`: `connected={Boolean(peerPubKey)}`).
    final connected = view.peerKey is! ChatPeerKeyAwaited;
    return Row(
      children: [
        Expanded(
          child: _Pill(
            text: l10n.p2pChatYouState(
              connected ? l10n.p2pChatConnected : l10n.p2pChatDisconnected,
            ),
            on: connected,
          ),
        ),
        const Gap(BullSpacing.sm),
        Expanded(
          child: _Pill(
            text: l10n.p2pChatPeerState(
              !connected
                  ? l10n.p2pChatWaitingShort
                  : view.peerConnected
                  ? l10n.p2pChatConnected
                  : l10n.p2pChatDisconnected,
            ),
            on: connected && view.peerConnected,
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final bool on;

  const _Pill({required this.text, required this.on});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: BullSpacing.xs,
        vertical: BullSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: on ? colors.success.withValues(alpha: 0.25) : colors.surface,
        borderRadius: BorderRadius.circular(BullRadius.xxs),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colors.onSurface),
      ),
    );
  }
}

/// The colour of a card, the reference's blue for the taker's messages and its purple for the maker's (`MessageCard/index.tsx`), from the theme.
Color _cardColor(BuildContext context, {required bool isTaker}) {
  final colors = context.bull;
  return (isTaker ? colors.info : colors.tertiary).withValues(alpha: 0.18);
}

/// The author's avatar with the reference's dot, green while connected and red otherwise (`MessageCard/index.tsx`: `statusColor`).
class _Author extends StatelessWidget {
  /// The robot's hash id, its face's seed everywhere in the app.
  final String face;
  final bool connected;

  const _Author({required this.face, required this.connected});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    return SizedBox.square(
      dimension: 28,
      child: Stack(
        children: [
          RobotAvatar(seed: face, size: 28),
          PositionedDirectional(
            end: 0,
            bottom: 0,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: connected ? colors.success : colors.error,
                border: Border.all(color: colors.surface),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One message (`MessageCard/index.tsx`): the author's avatar and nickname, the tick or the cross of its signature with the reference's tooltip, a copy of its text, the text, and the marks of the app.
class _MessageCard extends StatefulWidget {
  final ChatEntry entry;
  final String face;
  final bool isTaker;
  final bool connected;

  const _MessageCard({
    required this.entry,
    required this.face,
    required this.isTaker,
    required this.connected,
  });

  @override
  State<_MessageCard> createState() => _MessageCardState();
}

class _MessageCardState extends State<_MessageCard> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } on PlatformException {
      return;
    }
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final entry = widget.entry;
    final text = entry.text;
    // One expression for the icon, its colour and its words.
    final (signature, mark, markColor) = entry.validSignature
        ? (
            l10n.p2pChatSignatureVerified(entry.nick),
            Icons.check,
            colors.success,
          )
        : (
            l10n.p2pChatSignatureUnverified(entry.nick),
            Icons.close,
            colors.error,
          );
    // One stop for a screen reader per message, its signature said once (the tooltip's).
    return MergeSemantics(
      child: Card(
        color: _cardColor(context, isTaker: widget.isTaker),
        margin: const EdgeInsets.only(bottom: BullSpacing.xs),
        child: Padding(
          padding: const EdgeInsets.all(BullSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (entry.afterGap)
                _Line(
                  l10n.p2pChatMarkAfterGap,
                  color: colors.warning,
                  small: true,
                ),
              Row(
                children: [
                  _Author(face: widget.face, connected: widget.connected),
                  const Gap(BullSpacing.xs),
                  Expanded(
                    child: Tooltip(
                      message: signature,
                      triggerMode: TooltipTriggerMode.tap,
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              entry.nick,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: colors.textMuted),
                            ),
                          ),
                          Icon(mark, size: 16, color: markColor),
                        ],
                      ),
                    ),
                  ),
                  if (text != null)
                    IconButton(
                      tooltip: _copied
                          ? l10n.p2pCommonCopied
                          : l10n.p2pCommonCopy,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => unawaited(_copy(text)),
                      icon: Icon(
                        Icons.content_copy,
                        size: 16,
                        color: colors.textMuted,
                      ),
                    ),
                ],
              ),
              if (text != null)
                // Plain text in a forced direction: no markup, no link, nothing tappable, and no paragraph direction a peer's text could choose (review of #93).
                SelectableText(
                  text,
                  textDirection: TextDirection.ltr,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colors.onSurface),
                )
              else
                _Line(
                  entry.awaitingPeerKey
                      ? l10n.p2pChatWaitingForPeer
                      : l10n.p2pChatUnreadable,
                  color: colors.textMuted,
                  small: true,
                ),
              if (_copied)
                _Line(
                  l10n.p2pCommonCopied,
                  color: colors.textMuted,
                  small: true,
                  live: true,
                ),
              if (entry.repeatOf != null)
                _Line(
                  entry.sentTwice
                      ? l10n.p2pChatMarkSentTwice
                      : l10n.p2pChatMarkRepeat,
                  color: entry.sentTwice ? colors.textMuted : colors.warning,
                  small: true,
                ),
              if (entry.signedOutOfOrder)
                _Line(
                  l10n.p2pChatMarkOutOfOrder,
                  color: colors.warning,
                  small: true,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A message this robot sent that the coordinator does not show as stored: its text, « Not confirmed by … », and « Send again », the user's tap.
class _PendingCard extends StatelessWidget {
  final ChatPendingMessage pending;
  final String nick;
  final String face;
  final bool isTaker;
  final String coordinator;
  final bool sending;
  final VoidCallback? onSendAgain;

  const _PendingCard({
    required this.pending,
    required this.nick,
    required this.face,
    required this.isTaker,
    required this.coordinator,
    required this.sending,
    required this.onSendAgain,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    return Card(
      color: _cardColor(context, isTaker: isTaker),
      margin: const EdgeInsets.only(bottom: BullSpacing.xs),
      child: Padding(
        padding: const EdgeInsets.all(BullSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _Author(face: face, connected: true),
                const Gap(BullSpacing.xs),
                Expanded(
                  child: Text(
                    nick,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: colors.textMuted),
                  ),
                ),
              ],
            ),
            SelectableText(
              pending.text,
              textDirection: TextDirection.ltr,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurface),
            ),
            _Line(
              l10n.p2pChatNotConfirmed(coordinator),
              color: colors.warning,
              small: true,
              live: true,
            ),
            const Gap(BullSpacing.xs),
            TradeButton(
              label: l10n.p2pChatSendAgain,
              outlined: true,
              busy: sending,
              onPressed: onSendAgain,
            ),
          ],
        ),
      ),
    );
  }
}

/// A line of the panel; [live] read out when it appears.
class _Line extends StatelessWidget {
  final String text;
  final Color? color;
  final bool center;
  final bool small;
  final bool live;

  const _Line(
    this.text, {
    this.color,
    this.center = false,
    this.small = false,
    this.live = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Semantics(
      container: live,
      liveRegion: live,
      child: Text(
        text,
        textAlign: center ? TextAlign.center : TextAlign.start,
        style: (small ? theme.bodySmall : theme.bodyMedium)?.copyWith(
          color: color ?? context.bull.onSurface,
        ),
      ),
    );
  }
}
