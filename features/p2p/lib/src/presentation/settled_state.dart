import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

/// The first state of [cubit] that [settled] accepts, waited for at most [wait]; the state [cubit] has then when the wait ends first, or when [cubit] closes before such a state comes (a screen left meanwhile), so that a read that does not end never holds a tap: the wait of a tap on an order of the book for the active trades' read, and the wait of « Renew » for the renewals' read (#314).
///
/// Nothing is caught: a cubit's stream carries no error (`BlocBase.addError` tells the observer only), the end of a closed cubit's stream is answered by `orElse` and the end of the wait by `onTimeout`, so that an `Error` of [settled] reaches the caller (rule 11 of `AGENTS.md`).
Future<S> settledState<S>(
  BlocBase<S> cubit,
  bool Function(S state) settled, {
  required Duration wait,
}) => cubit.stream
    .firstWhere(settled, orElse: () => cubit.state)
    .timeout(wait, onTimeout: () => cubit.state);
