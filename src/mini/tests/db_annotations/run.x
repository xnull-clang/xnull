package app.db
import MemoryFixture
import generated.DbGenerated

class UserEntity {
    Long id
    String name
    Int age
    Bool active
    Double score
    UserEntity(Long id, String name, Int age, Bool active, Double score) {
        self.id = id
        self.name = name
        self.age = age
        self.active = active
        self.score = score
    }
}

class AuditEntity {
    Long id
    String action
    AuditEntity(Long id, String action) {
        self.id = id
        self.action = action
    }
}

class UserDao {
    Result<Long, Error> insertTx(SqlTransaction tx, UserEntity value) {
        Result<SqlResult, Error> inserted = tx.execute(UserEntityInsertStatement(value))
        if inserted.isErr() { return Err(inserted.error()) }
        return Ok(inserted.value().rowsAffected())
    }

    Result<Long, Error> insertThenFailTx(SqlTransaction tx, UserEntity value) {
        Result<SqlResult, Error> inserted = tx.execute(UserEntityInsertStatement(value))
        if inserted.isErr() { return Err(inserted.error()) }
        return Err(sqlInvalidArgument("rolled back"))
    }

    Result<Long, Error> failTx(SqlTransaction tx) {
        return Err(sqlInvalidArgument("boom"))
    }

    Result<Long, Error> readOnlyTx(SqlTransaction tx) {
        return Ok(1)
    }
}

static Int main() {
    MemoryConnection connection = new MemoryConnection()
    UserDao dao = new UserDao()
    print("table=" + UserEntityTableName())
    print("create=" + str(connection.execute(UserEntityCreateTableStatement()).isOk()))

    Result<Long, Error> first = UserEntityInsert(connection, new UserEntity(1, "Ada", 36, true, 1.5))
    print("insert=" + str(first.isOk()) + "," + str(first.value()))
    Result<Long, Error> second = UserEntityInsert(connection, new UserEntity(2, "Bob", 41, false, 2.5))
    print("insert2=" + str(second.value()))

    Result<UserEntity, Error> found = UserEntityFindById(connection, 1)
    UserEntity ada = found.value()
    print("find=" + str(ada.id) + "," + ada.name + "," + str(ada.age) + "," + str(ada.active) + "," + str(ada.score))

    Result<Long, Error> updated = UserEntityUpdate(connection, new UserEntity(2, "Bobby", 42, false, 3.5))
    print("update=" + str(updated.value()))
    UserEntity bobby = UserEntityFindById(connection, 2).value()
    print("updated=" + bobby.name + "," + str(bobby.age) + "," + str(bobby.score))

    Result<List<UserEntity>, Error> listed = UserEntityListAll(connection)
    print("list=" + str(listed.value().length()) + "," + listed.value().get(0).name + "," + listed.value().get(1).name)

    Result<Long, Error> deleted = UserEntityDeleteById(connection, 2)
    print("delete=" + str(deleted.value()) + "," + str(UserEntityListAll(connection).value().length()))
    Result<UserEntity, Error> gone = UserEntityFindById(connection, 2)
    print("deleted-find=" + str(gone.isErr()) + "," + str(gone.error().kind() == ErrorKind.NotFound))

    SqlStatement reordered = new SqlStatement("SELECT score, id, display_name, age, active FROM users WHERE id = ?")
    reordered = reordered.bind(SqlValue.ofLong(1))
    SqlResult reorderedResult = connection.execute(reordered).value()
    Result<UserEntity, Error> remapped = UserEntityFromRow(reorderedResult.rows().get(0), reorderedResult.columns())
    print("reordered=" + str(remapped.value().id) + "," + remapped.value().name + "," + str(remapped.value().score))

    List<SqlColumn> wrongColumns = []
    wrongColumns.push(new SqlColumn("id", "INT", true))
    List<SqlValue> wrongValues = []
    wrongValues.push(SqlValue.ofString("not-a-long"))
    Result<UserEntity, Error> wrongKind = UserEntityFromRow(new SqlRow(wrongValues), wrongColumns)
    print("wrong-kind=" + str(wrongKind.isErr()) + "," + str(wrongKind.error().kind() == ErrorKind.DataCorrupted))

    List<SqlColumn> missingColumns = []
    missingColumns.push(new SqlColumn("display_name", "TEXT", true))
    List<SqlValue> missingValues = []
    missingValues.push(SqlValue.ofString("Ada"))
    Result<UserEntity, Error> missing = UserEntityFromRow(new SqlRow(missingValues), missingColumns)
    print("missing-column=" + str(missing.isErr()) + "," + str(missing.error().kind() == ErrorKind.DataCorrupted))

    print("not-found=" + str(UserEntityFindById(connection, 99).error().kind() == ErrorKind.NotFound))
    print("table-annotation=" + AuditEntityTableName() + "," + str(connection.execute(AuditEntityCreateTableStatement()).isOk()))
    print("audit-insert=" + str(AuditEntityInsert(connection, new AuditEntity(7, "login")).value()) + "," + AuditEntityFindById(connection, 7).value().action)

    Result<Long, Error> committed = UserDao_insertTxTransactional(connection, dao, new UserEntity(10, "Tx", 30, true, 4.5))
    print("tx-commit=" + str(committed.isOk()) + "," + str(committed.value()) + "," + str(UserEntityFindById(connection, 10).isOk()))

    Result<Long, Error> rolled = UserDao_insertThenFailTxTransactional(connection, dao, new UserEntity(11, "Rollback", 31, true, 5.5))
    print("tx-rollback=" + str(rolled.isErr()) + "," + str(UserEntityFindById(connection, 11).isErr()))

    Result<Long, Error> failed = UserDao_failTxTransactional(connection, dao)
    print("tx-fail=" + str(failed.isErr()) + "," + str(failed.error().kind() == ErrorKind.InvalidArgument))

    connection.failNextCommit()
    Result<Long, Error> commitFailed = UserDao_insertTxTransactional(connection, dao, new UserEntity(12, "NoCommit", 32, true, 6.5))
    print("tx-commit-fail=" + str(commitFailed.isErr()) + "," + str(UserEntityFindById(connection, 12).isErr()))

    Result<Long, Error> readOnly = UserDao_readOnlyTxTransactional(connection, dao)
    print("tx-readonly=" + str(readOnly.isOk()) + "," + str(readOnly.value()))

    UserEntityInsert(connection, new UserEntity(99, "Dup", 1, true, 0.5))
    UserEntityInsert(connection, new UserEntity(99, "Dup", 2, true, 0.5))
    Result<UserEntity, Error> duplicate = UserEntityFindById(connection, 99)
    print("duplicate=" + str(duplicate.isErr()) + "," + str(duplicate.error().kind() == ErrorKind.DataCorrupted))
    return 0
}
