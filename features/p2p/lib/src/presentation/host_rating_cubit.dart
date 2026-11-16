import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../domain/trade/trade_chat_step.dart';
import '../domain/trade/trade_host_rating.dart';
import '../domain/trade/trade_watch.dart';
import '../domain/trade_record.dart';

/// Where « Rate your host » stands for the shown trade (#95).
sealed class HostRatingState {
  const HostRatingState();
}

/// The token was not asked yet: no shown status offered the rating.
final class HostRatingIdle extends HostRatingState {
  const HostRatingIdle();
}

/// The token is being asked to the coordinator: the stars wait for it.
final class HostRatingAsking extends HostRatingState {
  const HostRatingAsking();
}

/// The token is in hand: each tap of a star publishes a rating.
final class HostRatingReady extends HostRatingState {
  final HostReviewToken token;

  const HostRatingReady(this.token);
}

/// No token ([HostTokenNotGiven]): nothing can be published from this screen.
final class HostRatingUnavailable extends HostRatingState {
  const HostRatingUnavailable();
}

/// « Rate your host » of one shown trade (#95), over `RateHostUsecase`: the token asked once, the first time a shown status offers the rating, as the reference asks it once when it shows its stars; then each tap publishes once, without waiting, and nothing of the outcome is said, as in the reference.
class HostRatingCubit extends Cubit<HostRatingState> {
  final TradeRecord _record;
  final Future<Result<HostReviewToken, HostTokenNotGiven>> Function(
    TradeRecord record,
    TradeSeen seen,
  )
  _fetchToken;
  final Future<void> Function(
    TradeRecord record,
    TradeSeen seen,
    HostReviewToken token,
    HostRating rating,
  )
  _publish;

  HostRatingCubit(this._record, this._fetchToken, this._publish)
    : super(const HostRatingIdle());

  /// Asks for the token when [seen], the status shown, offers the rating and it was never asked in this screen.
  ///
  /// An `Error` of the use case leaves the stars off ([HostRatingUnavailable]) and is passed on.
  Future<void> show(TradeSeen seen) async {
    if (state is! HostRatingIdle || !ChatStepAction.rate.offeredAt(seen)) {
      return;
    }
    emit(const HostRatingAsking());
    var given = false;
    try {
      final result = await _fetchToken(_record, seen);
      if (isClosed) return;
      if (result case Ok(:final value)) {
        given = true;
        emit(HostRatingReady(value));
      }
    } finally {
      if (!given && !isClosed) emit(const HostRatingUnavailable());
    }
  }

  /// Publishes [rating] for [seen], the status shown at the tap, once the token is in hand; nothing otherwise.
  Future<void> rate(TradeSeen seen, HostRating rating) async {
    if (state case HostRatingReady(:final token)) {
      await _publish(_record, seen, token, rating);
    }
  }
}
