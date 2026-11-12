import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/ui/widgets/seed_hash.dart';

void main() {
  // The robots of the makers and the marks of the coordinators take their traits and colours from this hash: a change would redraw every one of them.
  test('the seed hash gives the same values at every run', () {
    expect(seedHash('temple'), 806777758);
    expect(seedHash('lake'), 980846952);
    expect(seedHash('bazaar'), 815202495);
    expect(seedHash('freeport'), 668793412);
    expect(seedHash('ammanaya'), 720506301);
    expect(seedHash('gumpellite'), 890993904);
  });
}
