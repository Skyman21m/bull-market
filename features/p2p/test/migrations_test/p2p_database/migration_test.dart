import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';

/// The schema of `p2p.sqlite` against its snapshots (`lib/src/data/schemas/`, written by `make drift-migrations`).
///
/// A change to the tables without a new version and its snapshot fails here; once a version ships, its snapshot never changes, and every later version adds an idempotent step from it.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('the version of the database is its last snapshot', () {
    expect(GeneratedHelper.versions.last, P2pDatabase.schema);
  });

  test('the tables of the database are those of its snapshot', () async {
    final schema = await verifier.schemaAt(P2pDatabase.schema);
    final database = P2pDatabase.forTesting(schema.newConnection());

    await verifier.migrateAndValidate(database, P2pDatabase.schema);
    await database.close();
  });

  // Each step from every older snapshot to every newer one, with no data: the first version has none yet.
  const versions = GeneratedHelper.versions;
  for (final (i, from) in versions.indexed) {
    for (final to in versions.skip(i + 1)) {
      test('migrates from $from to $to', () async {
        final schema = await verifier.schemaAt(from);
        final database = P2pDatabase.forTesting(schema.newConnection());

        await verifier.migrateAndValidate(database, to);
        await database.close();
      });
    }
  }

  test('a new database is created with the tables it declares', () async {
    final database = P2pDatabase.forTesting(NativeDatabase.memory());

    await database.validateDatabaseSchema();
    await database.close();
  });
}
