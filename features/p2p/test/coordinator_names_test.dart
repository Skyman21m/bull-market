import 'package:bull_ui/bull_ui.dart' show BullPickerSheet;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/book_filter.dart';
import 'package:p2p/src/domain/tor_wait.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/domain/usecases/load_federation_books_usecase.dart';
import 'package:p2p/src/domain/usecases/request_federation_books_usecase.dart';
import 'package:p2p/src/domain/usecases/retry_p2p_tor_usecase.dart';
import 'package:p2p/src/domain/usecases/start_p2p_tor_usecase.dart';
import 'package:p2p/src/domain/usecases/watch_p2p_tor_state_usecase.dart';
import 'package:p2p/src/presentation/book_cubit.dart';
import 'package:p2p/src/presentation/book_state.dart';
import 'package:p2p/src/presentation/order_details_cubit.dart';
import 'package:p2p/src/ui/book_view.dart';
import 'package:p2p/src/ui/order_details_screen.dart';
import 'package:p2p/src/ui/widgets/coordinators_row.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/book_attempts.dart';
import 'support/fakes.dart';
import 'support/harness.dart';

/// Temple under a name that holds a right-to-left override, a zero width space and a line break, far too long.
Coordinator _renamed() {
  final temple = coordinator('temple');
  return Coordinator(
    shortAlias: temple.shortAlias,
    longAlias:
        'Temple${String.fromCharCodes([0x202E, 0x200B, 0x0A])}${'W' * 200}',
    identifier: temple.identifier,
    description: temple.description,
    motto: temple.motto,
    color: temple.color,
    established: temple.established,
    nostrHexPubkey: temple.nostrHexPubkey,
    contact: temple.contact,
    badges: temple.badges,
    policies: temple.policies,
    mainnet: temple.mainnet,
    testnet: temple.testnet,
    mainnetNodesPubkeys: temple.mainnetNodesPubkeys,
    testnetNodesPubkeys: temple.testnetNodesPubkeys,
    federated: temple.federated,
  );
}

void main() {
  // The controls removed, the line break as a space, cut at 64 code points.
  final shown = 'Temple ${'W' * 57}…';
  final hostile = _renamed();
  late PublicOrder order;

  setUpAll(() async {
    final result = await CoordinatorClient(
      FakeTransport(
        books: {
          'temple': [bookOrder(id: 1)],
        },
      ),
      clock: () => testNow,
    ).fetchBook(hostile, RobosatsNetwork.mainnet);
    order = switch (result) {
      Ok(:final value) => value.orders.single,
      Err(:final failure) => throw StateError('$failure'),
    };
  });

  testWidgets('in the book: a coordinator still failing, and the host chosen', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final tor = FakeTor();
    final book = BookCubit(
      RobosatsNetwork.mainnet,
      WatchP2pTorStateUsecase(() => tor),
      StartP2pTorUsecase(() => tor),
      RetryP2pTorUsecase(() => tor),
      LoadFederationBooksUsecase(
        RequestFederationBooksUsecase(
          FederationBookReader(FakeTransport(), clock: () => testNow),
          Federation.robosats,
        ),
        FakeWaits().waits,
      ),
    );
    addTearDown(book.close);
    final state = BookState(
      network: RobosatsNetwork.mainnet,
      tor: TorWait.ready,
      coordinators: {
        hostile: const CoordinatorBookFailed(CoordinatorTimedOut()),
      },
      filter: BookFilter(host: hostile),
    );

    await tester.pumpWidget(
      harness(
        BlocProvider.value(
          value: book,
          child: Column(
            children: [
              BookFilterSentence(state: state),
              CoordinatorsRow(
                state: state,
                onOpenCoordinator: (_) {},
                onRetry: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text(shown), findsOneWidget);
    // The row says the name to a screen reader, cleaned the same way.
    expect(find.bySemanticsLabel('$shown, offline'), findsOneWidget);

    // The list of hosts the filter opens.
    await tester.tap(find.text(shown));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      find.descendant(
        of: find.byWidgetPredicate((widget) => widget is BullPickerSheet),
        matching: find.text(shown),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('on the page of an order: its host', (tester) async {
    usePhoneScreen(tester);
    final details = OrderDetailsCubit(
      order,
      RobosatsNetwork.mainnet,
      FetchCoordinatorInfoUsecase(CoordinatorClient(FakeTransport())),
    );
    addTearDown(details.close);

    await tester.pumpWidget(
      harness(
        BlocProvider.value(
          value: details,
          child: OrderDetailsScreen(
            now: () => testNow,
            coordinatorDetails: (_) => throw StateError('not opened'),
          ),
        ),
      ),
    );

    expect(find.text(shown), findsOneWidget);
  });
}
