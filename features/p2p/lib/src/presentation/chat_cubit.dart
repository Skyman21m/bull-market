import 'dart:async';
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';

import '../domain/trade/trade_chat.dart';
import '../domain/trade/trade_watch.dart';
import '../domain/trade_record.dart';
import '../domain/usecases/trade/send_chat_message_usecase.dart';
import '../domain/usecases/trade/watch_chat_usecase.dart';
import 'payout_cubit.dart' show TradeKeyHolder;

/// [WatchChatUsecase.read], which the locator gives the cubit.
typedef ChatReader =
    Future<Result<ChatView, ChatReadFailure>> Function(
      TradeRecord record,
      TradeSeen seen,
    );

/// [SendChatMessageUsecase.send], which the locator gives the cubit.
typedef ChatPoster =
    Future<Result<ChatSent, ChatSendRefusal>> Function(
      TradeRecord record,
      TradeSeen seen,
      String text,
    );

/// [SendChatMessageUsecase.sendAgain], which the locator gives the cubit.
typedef ChatReposter =
    Future<Result<ChatSent, ChatSendRefusal>> Function(
      TradeRecord record,
      TradeSeen seen,
      int id,
    );

/// [WatchChatUsecase.readNewerOnly], which the locator gives the cubit.
typedef ChatSkipper = ChatView Function(TradeRecord record, TradeSeen seen);

/// [WatchChatUsecase.current], which the locator gives the cubit.
typedef ChatCurrent = ChatView Function(TradeRecord record);

/// [WatchChatUsecase.exportOf], which the locator gives the cubit.
typedef ChatExporter = Map<String, Object?> Function(TradeRecord record);

/// Hands [text], a file named [fileName], to the system's share sheet, on the user's tap only: whoever places the chat's actions lends it (the feature declares no share package).
typedef ChatShare = Future<void> Function(String fileName, String text);

/// What the chat panel of one trade shows (#93): the chat as read, the text in the field, and what the last send and the last read gave.
@immutable
final class ChatPanelState {
  final ChatView view;

  /// The text of the field: the only copy, which the panel shows and « Send » sends, as typed.
  final String text;

  /// The id of the pending message being sent again, or `0` for the field's text, while a send runs; `null` otherwise.
  final int? sending;

  /// Why the field's text cannot be sent, said as the user types, or why the last send was refused; `null` otherwise.
  final ChatSendRefusal? refusal;

  /// Why the last read gave nothing new, while it is so; the chat as it was stays shown.
  final ChatReadFailure? readFailure;

  const ChatPanelState({
    this.view = const ChatView(),
    this.text = '',
    this.sending,
    this.refusal,
    this.readFailure,
  });

  /// Whether « Send » may be pressed: a text that can be sent, the peer's key known, nothing being sent.
  bool get canSend =>
      sending == null &&
      view.canSend &&
      SendChatMessageUsecase.refusalOf(text) == null;

  ChatPanelState _with({
    ChatView? view,
    String? text,
    int? Function()? sending,
    ChatSendRefusal? Function()? refusal,
    ChatReadFailure? Function()? readFailure,
  }) => ChatPanelState(
    view: view ?? this.view,
    text: text ?? this.text,
    sending: sending == null ? this.sending : sending(),
    refusal: refusal == null ? this.refusal : refusal(),
    readFailure: readFailure == null ? this.readFailure : readFailure(),
  );

  @override
  String toString() =>
      'ChatPanelState($view, sending: $sending, refusal: ${refusal.runtimeType})';
}

/// The chat panel of one shown trade (#93): the only caller of the chat use cases and, for the chat, of the key's hold, which the locator gives it as their members.
///
/// While [activate]d (the panel shown, the app in the foreground, its tab of the shell visible) it reads the chat at once and every [pollEvery], the reference's `CHAT_POLL_INTERVAL_MS` (`EncryptedApiChat/index.tsx:51`), one read at a time, and holds the robot's key so that each read decrypts without unlocking it again; [deactivate] stops both.
/// [send] sends the field's text as it is shown, once; a message not confirmed is sent again only by [sendAgain], the user's tap.
class ChatCubit extends Cubit<ChatPanelState> {
  final TradeRecord record;
  final ChatReader _read;
  final ChatPoster _post;
  final ChatReposter _repost;
  final ChatSkipper _skip;
  final ChatCurrent _current;
  final ChatExporter _export;
  final TradeKeyHolder _holdKey;
  final Duration _pollEvery;

  /// The reference's chat poll.
  static const pollEvery = Duration(seconds: 5);

  /// The status the trade screen last showed: what the reads and the sends are about.
  TradeSeen? _seen;
  Timer? _timer;
  bool _reading = false;
  void Function()? _hold;

  ChatCubit(
    this.record,
    this._read,
    this._post,
    this._repost,
    this._skip,
    this._current,
    this._export,
    this._holdKey, {
    this._pollEvery = ChatCubit.pollEvery,
  }) : super(ChatPanelState(view: _current(record)));

  /// Whether the robot's key is held: for the tests.
  @visibleForTesting
  bool get holdsKey => _hold != null;

  /// Whether the chat is read every [pollEvery]: for the tests.
  @visibleForTesting
  bool get polling => _timer != null;

  /// The panel is shown with [seen], the status the trade screen shows.
  void show(TradeSeen seen) => _seen = seen;

  /// The panel is shown, the app in the foreground: the key held, the chat read now and every [pollEvery]. A second call does nothing.
  void activate() {
    if (isClosed || _timer != null) return;
    _hold ??= _holdKey(record);
    _timer = Timer.periodic(_pollEvery, (_) => unawaited(_poll()));
    unawaited(_poll());
  }

  /// The panel left, the app hidden or paused, or another tab shown: no more reads, the key let go. A second call does nothing.
  void deactivate() {
    _timer?.cancel();
    _timer = null;
    final release = _hold;
    _hold = null;
    release?.call();
  }

  Future<void> _poll() async {
    final seen = _seen;
    if (isClosed || _reading || seen == null) return;
    _reading = true;
    try {
      final read = await _read(record, seen);
      if (isClosed) return;
      switch (read) {
        case Ok(:final value):
          emit(state._with(view: value, readFailure: () => null));
        case Err(:final failure):
          emit(state._with(readFailure: () => failure));
      }
    } finally {
      _reading = false;
    }
  }

  /// The field is [text], as typed: what cannot be sent is said at once.
  void edit(String text) {
    if (isClosed) return;
    final refusal = text.trim().isEmpty
        ? null
        : SendChatMessageUsecase.refusalOf(text);
    emit(state._with(text: text, refusal: () => refusal));
  }

  /// Sends the field's text as it is shown: nothing while a send runs, or when it cannot be sent.
  Future<void> send() async {
    final seen = _seen;
    final text = state.text;
    if (isClosed || seen == null || !state.canSend) return;
    emit(state._with(sending: () => 0, refusal: () => null));
    final sent = await _post(record, seen, text);
    if (isClosed) return;
    switch (sent) {
      case Ok():
        // Stored, or not confirmed and kept pending with its text: the field is free for the next one.
        emit(
          state._with(
            view: _current(record),
            text: state.text == text ? '' : state.text,
            sending: () => null,
          ),
        );
      // The reference empties the field of a text that holds the token (`EncryptedApiChat/index.tsx:210-214`).
      case Err(failure: final ChatTextHoldsToken failure):
        emit(
          state._with(text: '', sending: () => null, refusal: () => failure),
        );
      case Err(:final failure):
        emit(state._with(sending: () => null, refusal: () => failure));
    }
  }

  /// Sends again the pending message [id], the user's tap: the same encrypted message.
  Future<void> sendAgain(int id) async {
    final seen = _seen;
    if (isClosed || seen == null || state.sending != null) return;
    emit(state._with(sending: () => id, refusal: () => null));
    final sent = await _repost(record, seen, id);
    if (isClosed) return;
    switch (sent) {
      case Ok():
        emit(state._with(view: _current(record), sending: () => null));
      case Err(:final failure):
        emit(state._with(sending: () => null, refusal: () => failure));
    }
  }

  /// The user chose to read only the newer messages, the history being too large to read from the start.
  void readNewerOnly() {
    final seen = _seen;
    if (isClosed || seen == null) return;
    emit(state._with(view: _skip(record, seen)));
    unawaited(_poll());
  }

  /// The chat as the export gives it, as indented JSON (`complete_log_chat_<order id>.json`): what « Export » hands the share sheet, on the user's tap only.
  String exportJson() => _json(_export(record));

  /// The export's file name, the reference's (`Prompts/Chat.tsx:288`).
  String get exportFileName => 'complete_log_chat_${record.orderId}.json';

  /// The keys' part of the export, as indented JSON: what « Keys » of « Don't trust, verify » hands the share sheet.
  String keysJson() => _json(_export(record)['credentials']);

  /// Its file name, the reference's (`Dialogs/AuditPGP.tsx`).
  String get keysFileName => 'pgp_keys_${record.orderId}.json';

  /// The messages' part of the export, as indented JSON: what « Messages » of « Don't trust, verify » hands the share sheet.
  String messagesJson() => _json(_export(record)['messages']);

  /// Its file name, the reference's (`Dialogs/AuditPGP.tsx`).
  String get messagesFileName => 'pgp_messages_${record.orderId}.json';

  static String _json(Object? value) =>
      const JsonEncoder.withIndent('  ').convert(value);

  @override
  Future<void> close() {
    deactivate();
    return super.close();
  }
}
