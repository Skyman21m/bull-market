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

/// The image the official client shows for each coordinator of the embedded federation list, by short alias: the small version (80 by 80) of `frontend/static/federation/avatars/<alias>.small.webp`.
///
/// Each image is the coordinator operator's own artwork, distributed in the RoboSats repository under its AGPL-3.0 notice, and bundled by the decision of the owner of 2026-11-12 (`NOTICE.md`): it is removed on request.
/// The asset paths are these constants, keyed by the aliases of the embedded list: nothing a coordinator sends, and no other text, can name an asset.
/// `test/coordinator_images_test.dart` pins every (commit, blob) pair and checks each asset against its blob id; a coordinator added to the list with an image needs its row here, its blob checked against RoboSats, and its pin.
const coordinatorImages = <String, CoordinatorImage>{
  'temple': (
    asset: 'assets/coordinators/temple.small.webp',
    path: 'frontend/static/federation/avatars/temple.small.webp',
    commit: _reference,
    blob: '166ad7ed623aba45dc4cb84b71b36bd2dc8e111e',
  ),
  'lake': (
    asset: 'assets/coordinators/lake.small.webp',
    path: 'frontend/static/federation/avatars/lake.small.webp',
    commit: _reference,
    blob: 'c90d069fffa4f0dc0dc70d3e7f7341f5d40ecd76',
  ),
  'bazaar': (
    asset: 'assets/coordinators/bazaar.small.webp',
    path: 'frontend/static/federation/avatars/bazaar.small.webp',
    commit: _reference,
    blob: 'cbdaa1e17ba97eaf355905121990127a8eb57a9c',
  ),
  'freeport': (
    asset: 'assets/coordinators/freeport.small.webp',
    path: 'frontend/static/federation/avatars/freeport.small.webp',
    commit: _reference,
    blob: '13bd8f64d87ccd872eb4a0faaa8300f169edfec7',
  ),
  'ammanaya': (
    asset: 'assets/coordinators/ammanaya.small.webp',
    path: 'frontend/static/federation/avatars/ammanaya.small.webp',
    commit: _reference,
    blob: '041b4f19bae4d75b4a3e852ea92ad28a40bde06f',
  ),
  'gumpellite': (
    asset: 'assets/coordinators/gumpellite.small.webp',
    path: 'frontend/static/federation/avatars/gumpellite.small.webp',
    commit: _federation,
    blob: 'def8359b4f8939b668bcb795082e552e98939329',
  ),
};
