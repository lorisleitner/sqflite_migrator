library sqflite_migrator;

import 'package:flutter/widgets.dart';
import 'package:sqflite/sqlite_api.dart';

typedef Future<void> MigrationFn(DatabaseExecutor db);

class Migration {
  final int version;
  final MigrationFn migrationFn;

  Migration({@required this.version, @required this.migrationFn})
      : assert(version != null),
        assert(migrationFn != null);
}

class Migrator {
  final _migrations = List<Migration>();

  Migrator add(Migration migration) {
    assert(migration != null);

    if (_migrations.any((m) => m.version == migration.version)) {
      throw MigrationException("Duplicate migration version");
    }

    _migrations.add(migration);

    return this;
  }

  Future<int> migrate(Database database) async {
    assert(database != null);

    if (_migrations.isEmpty) {
      return 0;
    }

    _migrations.sort((left, right) => left.version.compareTo(right.version));

    final currentVersion = await database.getVersion();
    if (_migrations.last.version < currentVersion) {
      throw MigrationException("Database is too new");
    }

    var appliedMigrations = 0;

    await Future.forEach<Migration>(_migrations, (m) async {
      if (m.version <= currentVersion) {
        return;
      }

      await database.transaction((tx) async {
        await m.migrationFn(tx);

        // DatabaseExecutor has no setVersion so we manually set the pragma
        await tx.execute("PRAGMA `user_version` = ${m.version}");
      }, exclusive: true);

      ++appliedMigrations;
    });

    return appliedMigrations;
  }
}

class MigrationException implements Exception {
  final String message;

  MigrationException(this.message) : assert(message != null);
}
