package app.sql
import MemoryFixture
import generated.SqlGenerated

class UserRow {
    Long id
    String name
    Bool active
    Double score
    UserRow(Long id, String name, Bool active, Double score) {
        self.id = id
        self.name = name
        self.active = active
        self.score = score
    }
}

static Int main() {
    MemoryDriver driver = new MemoryDriver()
    Map<String, String> options = [:]
    SqlConnection connection = driver.open("memory://test/db", options).value()
    SqlStatement create = new SqlStatement("CREATE TABLE users (user_id INT, display_name TEXT, active INT, score DOUBLE)")
    print("create=" + str(connection.execute(create).isOk()))

    Result<Long, Error> firstInsert = UserDao_insertExecute(connection, 1, "Ada", true, 1.5)
    print("insert1=" + str(firstInsert.value()))
    Result<Long, Error> secondInsert = UserDao_insertExecute(connection, 2, "Bob", false, 2.5)
    print("insert2=" + str(secondInsert.value()))

    Result<UserRow, Error> found = UserDao_findExecute(connection, 1)
    UserRow ada = found.value()
    print("find=" + str(ada.id) + "," + ada.name + "," + str(ada.active) + "," + str(ada.score))

    Result<UserRow, Error> reordered = UserDao_findReorderedExecute(connection, 1)
    print("reordered=" + str(reordered.value().id) + "," + reordered.value().name)

    Result<List<UserRow>, Error> listed = UserDao_listExecute(connection)
    print("list=" + str(listed.value().length()) + "," + listed.value().get(1).name)

    Result<Long, Error> updated = UserDao_updateExecute(connection, "Bobby", 2)
    print("update=" + str(updated.value()))
    print("updated-name=" + UserDao_findExecute(connection, 2).value().name)

    Result<UserRow, Error> reversed = UserDao_findByNameAndIdExecute(connection, 2, "Bobby")
    print("reversed=" + str(reversed.value().id) + "," + reversed.value().name)

    Result<List<UserRow>, Error> byName = UserDao_byNameExecute(connection, "Bobby")
    print("by-name=" + str(byName.value().length()) + "," + byName.value().get(0).name)

    Result<UserRow, Error> missing = UserDao_findExecute(connection, 99)
    print("not-found=" + str(missing.isErr()) + "," + str(missing.error().kind() == ErrorKind.NotFound))

    UserDao_insertExecute(connection, 1, "Duplicate", true, 0.5)
    Result<UserRow, Error> duplicate = UserDao_findExecute(connection, 1)
    print("multiple=" + str(duplicate.isErr()) + "," + str(duplicate.error().kind() == ErrorKind.DataCorrupted))

    List<SqlColumn> mappingColumns = []
    mappingColumns.push(new SqlColumn("user_id", "INT", true))
    mappingColumns.push(new SqlColumn("display_name", "TEXT", true))
    mappingColumns.push(new SqlColumn("active", "INT", true))
    mappingColumns.push(new SqlColumn("score", "DOUBLE", true))

    List<SqlValue> wrongValues = []
    wrongValues.push(SqlValue.ofString("not-a-long"))
    wrongValues.push(SqlValue.ofString("x"))
    wrongValues.push(SqlValue.ofBool(true))
    wrongValues.push(SqlValue.ofDouble(0.0))
    Result<UserRow, Error> wrongKind = UserRowFromRow(new SqlRow(wrongValues), mappingColumns)
    print("wrong-kind=" + str(wrongKind.isErr()) + "," + wrongKind.error().describe())

    List<SqlColumn> missingColumns = []
    missingColumns.push(new SqlColumn("other", "INT", true))
    List<SqlValue> oneValue = []
    oneValue.push(SqlValue.ofLong(1))
    Result<UserRow, Error> missingColumn = UserRowFromRow(new SqlRow(oneValue), missingColumns)
    print("missing-column=" + str(missingColumn.isErr()) + "," + missingColumn.error().describe())

    Result<UserRow, Error> shortRow = UserRowFromRow(new SqlRow(oneValue), mappingColumns)
    print("short-row=" + str(shortRow.isErr()) + "," + shortRow.error().describe())

    print("statement=" + UserDao_findStatement(7).describe())
    print("statement-params=" + str(UserDao_findStatement(7).parameterCount()) + "," + str(UserDao_findStatement(7).isNamedParameters()))
    return 0
}
