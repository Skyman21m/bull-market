/// The source of a coordinator image bundled with the feature: the asset, and the RoboSats file it is a byte-for-byte copy of, with the commit it was taken at and its Git blob id, which `git rev-parse <commit>:<path>` prints.
typedef CoordinatorImage = ({
  String asset,
  String path,
  String commit,
  String blob,
});

/// The commit of the RoboSats protocol reference, where five of the images were taken.
const _reference = 'ff1998caed30888b2fb60e15022c29063a60f1ba';

/// The commit the embedded federation list comes from, which adds Gumpellite and its image.
const _federation = 'e56f9cf7cd4e6b01aa78589922f7c648f262b6b6';

/// The image the official client shows for each coordinator of the embedded federation list, by short alias: `frontend/static/federation/avatars/<alias>.webp`, 200 by 200 pixels, the version its Android app loads for every use.
///
/// Each image is the coordinator operator's own artwork, distributed in the RoboSats repository under its AGPL-3.0 notice, and bundled by the decision of the owner of 2026-11-12 (`NOTICE.md`): it is removed on request.
/// The asset paths are these constants, keyed by the aliases of the embedded list: nothing a coordinator sends, and no other text, can name an asset.
/// `test/coordinator_images_test.dart` pins every (commit, blob) pair; `test/features/p2p/p2p_coordinator_images_test.dart`, in the app, recomputes the blob of each asset its bundle serves.
/// A coordinator added to the list with an image needs its row here, its blob checked against RoboSats, and its pin.
const coordinatorImages = <String, CoordinatorImage>{
  'temple': (
    asset: 'assets/coordinators/temple.webp',
    path: 'frontend/static/federation/avatars/temple.webp',
    commit: _reference,
    blob: '01172a3738529ee58d554d92f57fd0e9085a22ee',
  ),
  'lake': (
    asset: 'assets/coordinators/lake.webp',
    path: 'frontend/static/federation/avatars/lake.webp',
    commit: _reference,
    blob: '8936c1cd93d8b0599c47522d5a83133c83cc0415',
  ),
  'bazaar': (
    asset: 'assets/coordinators/bazaar.webp',
    path: 'frontend/static/federation/avatars/bazaar.webp',
    commit: _reference,
    blob: '816a7c8478bcb72908f5bda2f104d468c222bb7f',
  ),
  'freeport': (
    asset: 'assets/coordinators/freeport.webp',
    path: 'frontend/static/federation/avatars/freeport.webp',
    commit: _reference,
    blob: '56b583ac77d992df27300cf0851d8e6d70439158',
  ),
  'ammanaya': (
    asset: 'assets/coordinators/ammanaya.webp',
    path: 'frontend/static/federation/avatars/ammanaya.webp',
    commit: _reference,
    blob: 'ebaa03a3cd2b923c07efc78a3dad4453afe51a3f',
  ),
  'gumpellite': (
    asset: 'assets/coordinators/gumpellite.webp',
    path: 'frontend/static/federation/avatars/gumpellite.webp',
    commit: _federation,
    blob: 'b625b66c3052eb46260bb915ba4aca5e15a0d319',
  ),
};
