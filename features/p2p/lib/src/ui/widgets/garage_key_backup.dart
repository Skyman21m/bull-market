import 'package:flutter/widgets.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../../domain/network_garage_key.dart';
import '../../domain/trade/trade_take.dart';
import '../garage/garage_reauthentication.dart';
import 'garage_key_clipboard.dart';

/// What « Back it up! » of « Store your garage key » needs to copy the external Garage Key before a make or a take (#318, decided on 2026-11-28): the wallet's re-authentication the Garage asks before it shows a key (the same one the shell lends the Garage, `P2pFeature.route(reauthenticate:)`), the Garage's clipboard helper, and the reads of the key a make or a take uses, which give it only when it is the external one.
///
/// It holds no key: [GarageKeyCopy.read] reads it when the copy is asked, after the re-authentication.
@immutable
final class GarageKeyBackup {
  final P2pReauthentication reauthenticate;
  final GarageKeyClipboard clipboard;
  final Future<NetworkGarageKey?> Function(RobosatsNetwork network) _ofMake;
  final Future<NetworkGarageKey?> Function(PreparedTake prepared) _ofTake;

  const GarageKeyBackup({
    required this.reauthenticate,
    required this.clipboard,
    required this._ofMake,
    required this._ofTake,
  });

  /// The copy of the key a make on [network] would take.
  GarageKeyCopy ofMake(RobosatsNetwork network) =>
      GarageKeyCopy._(reauthenticate, clipboard, () => _ofMake(network));

  /// The copy of the key of the robot that will take [prepared].
  GarageKeyCopy ofTake(PreparedTake prepared) =>
      GarageKeyCopy._(reauthenticate, clipboard, () => _ofTake(prepared));
}

/// The copy of one trade's Garage Key: [reauthenticate] first, then [read], then [clipboard].
@immutable
final class GarageKeyCopy {
  final P2pReauthentication reauthenticate;
  final GarageKeyClipboard clipboard;

  /// The external Garage Key the trade uses, `null` when it is not the external one or cannot be read: called only once [reauthenticate] passed.
  final Future<NetworkGarageKey?> Function() read;

  const GarageKeyCopy._(this.reauthenticate, this.clipboard, this.read);
}

/// The [GarageKeyBackup] of the pages under it, which the router puts above the pages that make or take; `null` where the shell lends no re-authentication or the feature has no Garage: « Back it up! » then copies nothing.
class GarageKeyBackupScope extends InheritedWidget {
  final GarageKeyBackup? backup;

  const GarageKeyBackupScope({
    super.key,
    required this.backup,
    required super.child,
  });

  /// The backup above [context], read once when the reminder opens.
  static GarageKeyBackup? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<GarageKeyBackupScope>()?.backup;

  @override
  bool updateShouldNotify(GarageKeyBackupScope oldWidget) =>
      backup != oldWidget.backup;
}
