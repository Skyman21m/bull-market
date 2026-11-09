import 'dart:convert';
import 'dart:io';

/// The reference values of `test/fixtures/vecteurs-identite-robot.json`.
///
/// The file is a verbatim copy of `docs/spikes/vecteurs-identite-robot.json` of the Troc project notes, generated on 2026-11-09 against RoboSats commit ff1998c.
/// Its `_avertissement` and `_comment_chaque_valeur_est_produite` fields state how each value was produced and which ones come straight from the RoboSats repository.
/// Tests run with the package directory as working directory, as `make unit-test` does.
final Map<String, dynamic> vectors =
    jsonDecode(
          File('test/fixtures/vecteurs-identite-robot.json').readAsStringSync(),
        )
        as Map<String, dynamic>;

List<Map<String, dynamic>> _maps(Object? list) =>
    (list as List<dynamic>).cast<Map<String, dynamic>>();

/// The three robots of `tests/robots/{1,2,3}/` in the RoboSats repository.
List<Map<String, dynamic>> get repositoryRobots =>
    _maps(vectors['robots_de_test_robosats']);

/// The example Garage Key of `frontend/src/utils/__tests__/garageKey.test.ts`.
Map<String, dynamic> get garageKeyVector =>
    vectors['garage_key'] as Map<String, dynamic>;

/// The robots derived from the example Garage Key at indexes 0, 1 and 18.
List<Map<String, dynamic>> get garageKeyRobots =>
    _maps(garageKeyVector['derived']);

/// The robot whose nickname needs a re-hash (index 0).
Map<String, dynamic> get nicknameRehashRobot =>
    (vectors['cas_limites'] as Map<String, dynamic>)['nickname_rehash']
        as Map<String, dynamic>;

/// The robot whose base91 token hash is 39 characters long (index 6).
Map<String, dynamic> get base91ShortRobot =>
    (vectors['cas_limites'] as Map<String, dynamic>)['base91_39_chars']
        as Map<String, dynamic>;

/// Every robot of the vectors file, labelled for test names.
Map<String, Map<String, dynamic>> get allRobots => {
  for (final robot in repositoryRobots) robot['source'] as String: robot,
  for (final robot in garageKeyRobots)
    'garage key ${robot['derivation_path']}': robot,
  'edge case nickname re-hash': nicknameRehashRobot,
  'edge case base91 of 39 characters': base91ShortRobot,
};

/// The 200 nicknames produced by the RoboSats coordinator's own Python code.
List<Map<String, dynamic>> get referenceNicknames => _maps(
  (vectors['jeu_de_pseudos_reference'] as Map<String, dynamic>)['vecteurs'],
);

/// The first-contact `Authorization` header built from the keys of test robot 1.
String get firstContactHeaderExample =>
    (vectors['exemple_entete_premier_contact']
            as Map<String, dynamic>)['authorization']
        as String;
