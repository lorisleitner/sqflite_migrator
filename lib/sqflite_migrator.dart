library sqflite_migrator;

import 'package:flutter/widgets.dart';
import 'package:sqflite/sqlite_api.dart';

/// Defines the type of a migration function
typedef Future<void> MigrationFn(DatabaseExecutor db);

/// A single database migration
///
/// A migration has a version and a migration function that's executed
/// when the migration is applied.
class Migration {

  /// Migration version
  final int version;

  /// Migration function
  final MigrationFn migrationFn;

  Migration({@required this.version, @required this.migrationFn})
      : assert(version != null),
        assert(migrationFn != null);
}

/// Represents a database migrator, the main component of this library
///
/// A migrator executes pending migrations and updates the database version
class Migrator {
  final _migrations = List<Migration>();

  /// Add a migration to the list of migrations
  ///
  /// Migrations don't have to be in a particular order to be added, they are sorted
  /// when they're executed.
  /// Throws [MigrationException] if the migrator already contains a migration
  /// with the same version.
  Migrator add(Migration migration) {
    assert(migration != null);

    if (_migrations.any((m) => m.version == migration.version)) {
      throw MigrationException("Duplicate migration version");
    }

    _migrations.add(migration);

    return this;
  }

  /// Migrates [database] to the newest version
  ///
  /// Database must be open and ready.
  /// Database version is stored in SQLite's user_version.
  /// Migrations are applied in separate exclusive transactions
  /// so the migration function must not begin a new transaction.
  /// Returns a future that contains the number of migrations that were applied to the database.
  /// Throws [MigrationException] if database is too new to be migrated.
  /// Throws any exception from sqflite
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

/// Exception type for migrations
class MigrationException implements Exception {
  final String message;

  MigrationException(this.message) : assert(message != null);
}
