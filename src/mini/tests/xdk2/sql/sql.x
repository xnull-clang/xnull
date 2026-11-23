package xdk2.sql
import xdk.sql
import xdk.errors
import xdk.bytes
import xdk.math
import xdk.net.uri
import MemoryFixture

static String memText(SqlValue value) {
    return value.asString().value()
}

static Int memInt(SqlValue value) {
    return value.asInt().value()
}

static Int main() {
    // ---- SqlValue ----
    print("value-null=" + str(SqlValue.nullValue().isNull()) + "," + sqlKindName(SqlValue.nullValue().kind()))
    print("value-bool=" + str(SqlValue.ofBool(true).asBool().value()) + "," + sqlKindName(SqlValue.ofBool(true).kind()))
    print("value-int=" + str(SqlValue.ofInt(7).asInt().value()) + "," + sqlKindName(SqlValue.ofInt(7).kind()))
    print("value-long=" + str(SqlValue.ofLong(9000000000).asLong().value()) + "," + sqlKindName(SqlValue.ofLong(9000000000).kind()))
    print("value-double=" + str(SqlValue.ofDouble(1.5).asDouble().value()) + "," + sqlKindName(SqlValue.ofDouble(1.5).kind()))
    print("value-string=" + SqlValue.ofString("abc").asString().value() + "," + sqlKindName(SqlValue.ofString("abc").kind()))
    Bytes valueBytes = SqlValue.ofBytes(Bytes.fromString("xy")).asBytes().value()
    String valueBytesText = valueBytes.toString()
    print("value-bytes=" + valueBytesText + "," + sqlKindName(SqlValue.ofBytes(Bytes.fromString("xy")).kind()))
    print("value-wrong=" + str(SqlValue.ofInt(1).asString().isErr()))
    print("value-equals=" + str(SqlValue.ofInt(1).equals(SqlValue.ofInt(1))) + "," + str(SqlValue.ofInt(1).equals(SqlValue.ofLong(1))) + "," + str(SqlValue.ofDouble(NaN()).equals(SqlValue.ofDouble(NaN()))))
    print("value-describe=" + SqlValue.ofLong(2).describe())

    // ---- parameter / statement ----
    SqlParameter indexed = SqlParameter.indexed(1, SqlValue.ofString("a"))
    SqlParameter named = SqlParameter.named("userId", SqlValue.ofLong(42))
    print("parameter=" + indexed.describe() + "|" + named.describe())
    print("parameter-flags=" + str(indexed.isIndexed()) + "," + str(indexed.isNamed()) + "," + str(named.isNamed()) + "," + str(named.parameterIndex()))
    print("parameter-equals=" + str(indexed.equals(SqlParameter.indexed(1, SqlValue.ofString("a")))))
    SqlStatement statement = new SqlStatement("select * from users where id = ?")
    statement = statement.bind(SqlValue.ofInt(1))
    statement = statement.bind(SqlValue.ofString("x"))
    print("statement=" + str(statement.parameterCount()) + "," + str(statement.isNamedParameters()) + "," + statement.describe())
    SqlStatement namedStatement = new SqlStatement("select * from users where id = :id")
    namedStatement = namedStatement.withParameter(SqlParameter.named("id", SqlValue.ofInt(1)))
    print("statement-named=" + str(namedStatement.parameterCount()) + "," + str(namedStatement.isNamedParameters()))
    print("statement-clear=" + str(statement.clear().parameterCount()) + "," + str(statement.parameterCount()))
    print("statement-equals=" + str(statement.equals(statement.bind(SqlValue.ofBool(true)).clear().bind(SqlValue.ofInt(1)).bind(SqlValue.ofString("x")))))

    // ---- row / result ----
    List<SqlValue> rowValues = []
    rowValues.push(SqlValue.ofInt(1))
    rowValues.push(SqlValue.ofString("Ada"))
    SqlRow row = new SqlRow(rowValues)
    print("row=" + str(row.length()) + "," + row.get(1).asString().value() + "," + str(row.tryGet(2) == null) + "," + row.describe())
    List<SqlColumn> columns = []
    columns.push(new SqlColumn("id", "INT", false))
    columns.push(new SqlColumn("name", "TEXT", true))
    List<SqlRow> rows = []
    rows.push(row)
    SqlResult result = new SqlResult(columns, rows, 0, true)
    print("result=" + str(result.columnCount()) + "," + str(result.rowCount()) + "," + str(result.isQuery()) + "," + result.describe())
    List<SqlRow> snapshot = result.rows()
    snapshot.push(row)
    print("result-snapshot=" + str(result.rowCount()))
    print("result-equals=" + str(result.equals(new SqlResult(columns, rows, 0, true))))

    // ---- options / names ----
    SqlOptions options = new SqlOptions()
    options = options.timeoutMillis(2000).maxRows(10).fetchSize(5)
    SqlOptions optionsCopy = options.copy()
    optionsCopy.maxRows(20)
    print("options=" + str(options.getTimeoutMillis()) + "," + str(options.getMaxRows()) + "," + str(options.getFetchSize()) + "," + str(optionsCopy.getMaxRows()) + "," + options.describe())
    print("names=" + sqlDialectName(SqlDialect.Postgres) + "," + sqlDialectName(SqlDialect.Generic) + "," + sqlKindName(SqlKind.Bytes))

    // ---- memory driver ----
    MemoryDriver driver = new MemoryDriver()
    print("driver-name=" + driver.name())
    Map<String, String> openOptions = [:]
    openOptions.put("readonly", "false")
    Result<SqlConnection, Error> opened = driver.open("memory://test/db", openOptions)
    print("driver-open=" + str(opened.isOk()))
    SqlConnection connection = opened.value()
    print("connection=" + sqlDialectName(connection.dialect()) + "," + str(connection.isOpen()))

    SqlStatement create = new SqlStatement("CREATE TABLE users (id INT, name TEXT)")
    print("create=" + str(connection.execute(create).isOk()))

    SqlStatement insert = new SqlStatement("INSERT INTO users VALUES (?, ?)")
    insert = insert.bind(SqlValue.ofInt(1)).bind(SqlValue.ofString("Ada"))
    SqlResult insertResult = connection.execute(insert).value()
    print("insert=" + str(insertResult.rowsAffected()) + "," + str(insertResult.isQuery()))
    SqlStatement insert2 = new SqlStatement("INSERT INTO users VALUES (?, ?)")
    insert2 = insert2.bind(SqlValue.ofInt(2)).bind(SqlValue.ofString("Bob"))
    connection.execute(insert2)

    SqlStatement select = new SqlStatement("SELECT id, name FROM users")
    SqlResult selectResult = connection.execute(select).value()
    print("select=" + str(selectResult.rowCount()) + "," + str(selectResult.columnCount()) + "," + str(memInt(selectResult.rows().get(0).get(0))) + "," + memText(selectResult.rows().get(0).get(1)))

    SqlStatement where = new SqlStatement("SELECT id, name FROM users WHERE name = ?")
    where = where.bind(SqlValue.ofString("Bob"))
    SqlResult whereResult = connection.execute(where).value()
    print("where=" + str(whereResult.rowCount()) + "," + str(memInt(whereResult.rows().get(0).get(0))))

    SqlStatement limit = new SqlStatement("SELECT * FROM users")
    SqlOptions limitOptions = new SqlOptions()
    limitOptions = limitOptions.maxRows(1)
    print("maxrows=" + str(connection.executeWithOptions(limit, limitOptions).value().rowCount()))

    SqlStatement update = new SqlStatement("UPDATE users SET name = ? WHERE id = ?")
    update = update.bind(SqlValue.ofString("Bobby")).bind(SqlValue.ofInt(2))
    print("update=" + str(connection.execute(update).value().rowsAffected()))
    SqlStatement checkUpdate = new SqlStatement("SELECT name FROM users WHERE id = ?")
    checkUpdate = checkUpdate.bind(SqlValue.ofInt(2))
    print("update-value=" + memText(connection.execute(checkUpdate).value().rows().get(0).get(0)))

    SqlStatement delete = new SqlStatement("DELETE FROM users WHERE id = ?")
    delete = delete.bind(SqlValue.ofInt(1))
    print("delete=" + str(connection.execute(delete).value().rowsAffected()))
    print("delete-count=" + str(connection.execute(select).value().rowCount()))

    // ---- transaction commit ----
    SqlTransaction transaction = connection.begin().value()
    SqlStatement txInsert = new SqlStatement("INSERT INTO users VALUES (?, ?)")
    txInsert = txInsert.bind(SqlValue.ofInt(3)).bind(SqlValue.ofString("Cara"))
    transaction.execute(txInsert)
    print("tx-isolation=" + str(connection.execute(select).isErr()))
    print("tx-commit=" + str(transaction.commit().isOk()) + "," + str(transaction.isOpen()))
    print("tx-count=" + str(connection.execute(select).value().rowCount()))

    // ---- transaction rollback ----
    SqlTransaction rollbackTx = connection.begin().value()
    SqlStatement txInsert2 = new SqlStatement("INSERT INTO users VALUES (?, ?)")
    txInsert2 = txInsert2.bind(SqlValue.ofInt(4)).bind(SqlValue.ofString("Dora"))
    rollbackTx.execute(txInsert2)
    print("rollback=" + str(rollbackTx.rollback().isOk()) + "," + str(rollbackTx.isOpen()))
    print("rollback-count=" + str(connection.execute(select).value().rowCount()))

    // ---- transaction close auto rollback ----
    SqlTransaction closeTx = connection.begin().value()
    SqlStatement txInsert3 = new SqlStatement("INSERT INTO users VALUES (?, ?)")
    txInsert3 = txInsert3.bind(SqlValue.ofInt(5)).bind(SqlValue.ofString("Eve"))
    closeTx.execute(txInsert3)
    print("close-tx=" + str(closeTx.close().isOk()) + "," + str(closeTx.isOpen()))
    print("close-count=" + str(connection.execute(select).value().rowCount()))

    // ---- errors ----
    SqlStatement badNamed = new SqlStatement("SELECT * FROM users WHERE id = :id")
    badNamed = badNamed.withParameter(SqlParameter.named("id", SqlValue.ofInt(1)))
    print("named-execute=" + str(connection.execute(badNamed).isOk()))
    Map<String, String> badOptions = [:]
    badOptions.put("bogus", "x")
    print("bad-option=" + str(driver.open("memory://x", badOptions).isErr()))
    Map<String, String> emptyOptions = [:]
    print("bad-scheme=" + str(driver.open("other://x", emptyOptions).isErr()))
    print("close=" + str(connection.close().isOk()) + "," + str(connection.isOpen()))
    print("closed-execute=" + str(connection.execute(select).isErr()))
    print("closed-begin=" + str(connection.begin().isErr()))
    print("closed-dialect=" + sqlDialectName(connection.dialect()))
    print("close-idempotent=" + str(connection.close().isOk()))
    return 0
}
