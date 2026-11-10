import 'package:bb_mobile/features/exchange/public/exchange_facade.dart';
import 'package:bb_mobile/shell_tabs.dart';
import 'package:flutter_test/flutter_test.dart';

// The bottom bar of the shell as `lib/router.dart` builds it: which tabs, which one is current, and when the P2P tab must be left.
void main() {
  final exchange = ExchangeRoute.exchangeHome.path;

  group('gate open', () {
    test('Wallet, P2P, Exchange', () {
      final tabs = shellTabs(showP2p: true);

      expect(tabs, [ShellTab.wallet, ShellTab.p2p, ShellTab.exchange]);
      expect(tabs.indexOf(ShellTab.exchange), 2);
    });

    test('each location has its tab', () {
      expect(shellTabOf('/wallet', showP2p: true), ShellTab.wallet);
      expect(shellTabOf('/p2p', showP2p: true), ShellTab.p2p);
      expect(shellTabOf('/p2p/order', showP2p: true), ShellTab.p2p);
      expect(shellTabOf('/p2px', showP2p: true), ShellTab.wallet);
      expect(shellTabOf(exchange, showP2p: true), ShellTab.exchange);
    });

    test('the P2P tab is never left', () {
      expect(mustLeaveP2p('/p2p', showP2p: true), isFalse);
      expect(mustLeaveP2p('/p2p/order', showP2p: true), isFalse);
    });
  });

  group('gate closed', () {
    test('Wallet, Exchange: the bar is as before P2P', () {
      final tabs = shellTabs(showP2p: false);

      expect(tabs, [ShellTab.wallet, ShellTab.exchange]);
      expect(tabs.indexOf(ShellTab.exchange), 1);
    });

    test('a P2P location counts as the wallet', () {
      expect(shellTabOf('/p2p', showP2p: false), ShellTab.wallet);
      expect(shellTabOf('/p2p/order', showP2p: false), ShellTab.wallet);
      expect(shellTabOf(exchange, showP2p: false), ShellTab.exchange);
    });

    test('an open P2P tab is left for the wallet, nothing else is', () {
      expect(mustLeaveP2p('/p2p', showP2p: false), isTrue);
      expect(mustLeaveP2p('/p2p/order', showP2p: false), isTrue);
      expect(mustLeaveP2p('/p2px', showP2p: false), isFalse);
      expect(mustLeaveP2p('/wallet', showP2p: false), isFalse);
      expect(mustLeaveP2p(exchange, showP2p: false), isFalse);
    });
  });
}
