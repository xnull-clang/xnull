package app.sql
import MemoryFixture
import generated.SqlGenerated

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

    Result<List<UserRow>, Error> listed = UserDao_listExecute(connection)
    print("list=" + str(listed.value().length()) + "," + listed.value().get(1).name)

    Result<Long, Error> updated = UserDao_updateExecute(connection, "Bobby", 2)
    print("update=" + str(updated.value()))
    print("updated-name=" + UserDao_findExecute(connection, 2).value().name)

    Result<List<UserRow>, Error> byName = UserDao_byNameExecute(connection, "Bobby")
    print("by-name=" + str(byName.value().length()) + "," + byName.value().get(0).name)

    Result<UserRow, Error> missing = UserDao_findExecute(connection, 99)
    print("not-found=" + str(missing.isErr()) + "," + str(missing.error().kind() == ErrorKind.NotFound))

    UserDao_insertExecute(connection, 1, "Duplicate", true, 0.5)
    Result<UserRow, Error> duplicate = UserDao_findExecute(connection, 1)
    print("multiple=" + str(duplicate.isErr()) + "," + str(duplicate.error().kind() == ErrorKind.DataCorrupted))

    List<SqlValue> wrongValues = []
    wrongValues.push(SqlValue.ofString("not-a-long"))
    wrongValues.push(SqlValue.ofString("x"))
    wrongValues.push(SqlValue.ofBool(true))
    wrongValues.push(SqlValue.ofDouble(0.0))
    Result<UserRow, Error> wrongKind = UserRowFromRow(new SqlRow(wrongValues))
    print("wrong-kind=" + str(wrongKind.isErr()) + "," + wrongKind.error().describe())

    List<SqlValue> shortValues = []
    shortValues.push(SqlValue.ofLong(1))
    Result<UserRow, Error> shortRow = UserRowFromRow(new SqlRow(shortValues))
    print("short-row=" + str(shortRow.isErr()) + "," + shortRow.error().describe())

    print("statement=" + UserDao_findStatement(7).describe())
    print("statement-params=" + str(UserDao_findStatement(7).parameterCount()) + "," + str(UserDao_findStatement(7).isNamedParameters()))
    return 0
}
