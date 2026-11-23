// Shared in-memory SQL driver fixture for M6 tests (not public API).
package xdk2.sql
import xdk.bytes
import xdk.errors
import xdk.math
import xdk.net.uri
import xdk.sql

static Error memError(ErrorKind kind, String message) {
    BasicError error = new BasicError(kind, message)
    return error
}

static SqlResult memResult(List<SqlColumn> columns, List<SqlRow> rows, Long affected, Bool query) {
    return new SqlResult(columns, rows, affected, query)
}

static String memNorm(String text) {
    List<String> parts = text.trim().split(" ")
    String result = ""
    Int index = 0
    while index < parts.length() {
        String part = parts.get(index)
        if part != "" {
            if result != "" { result = result + " " }
            result = result + part
        }
        index = index + 1
    }
    return result
}

static Int memParamCount(String sql) {
    Int count = 0
    Int index = 0
    while index < sql.length() {
        String current = sql.substring(index, 1)
        if current == "?" { count = count + 1 }
        else if current == ":" && index + 1 < sql.length() {
            String next = sql.substring(index + 1, 1)
            if next != ":" { count = count + 1 }
        }
        index = index + 1
    }
    return count
}

static Bool memIsPlaceholder(String text) {
    if text == "?" { return true }
    return text.startsWith(":")
}

static Result<List<SqlValue>, Error> memValues(SqlStatement statement) {
    List<SqlParameter> parameters = statement.parameters()
    List<SqlValue> values = []
    Int index = 0
    while index < parameters.length() {
        SqlParameter parameter = parameters.get(index)
        values.push(parameter.value())
        index = index + 1
    }
    if values.length() != memParamCount(statement.sql()) {
        return Err(sqlInvalidArgument("parameter count mismatch"))
    }
    return Ok(values)
}

class MemTable {
    String name
    List<String> columnNames
    List<String> columnTypes
    List<List<SqlValue>> rows

    MemTable(String name, List<String> columnNames, List<String> columnTypes) {
        self.name = name
        self.columnNames = columnNames
        self.columnTypes = columnTypes
        self.rows = []
    }

    MemTable copy() {
        List<String> names = self.columnNames.copy()
        List<String> types = self.columnTypes.copy()
        MemTable result = new MemTable(self.name, names, types)
        Int index = 0
        while index < self.rows.length() {
            result.rows.push(self.rows.get(index).copy())
            index = index + 1
        }
        return result
    }

    Int columnIndex(String column) {
        Int index = 0
        while index < self.columnNames.length() {
            if self.columnNames.get(index) == column { return index }
            index = index + 1
        }
        return -1
    }
}

static List<MemTable> memCopyTables(List<MemTable> tables) {
    List<MemTable> result = []
    Int index = 0
    while index < tables.length() {
        result.push(tables.get(index).copy())
        index = index + 1
    }
    return result
}

static MemTable? memFindTable(List<MemTable> tables, String name) {
    Int index = 0
    while index < tables.length() {
        if tables.get(index).name == name { return tables.get(index) }
        index = index + 1
    }
    return null
}

static Result<SqlValue, Error> memColumnValue(String text, List<SqlValue> values) {
    if text == "?" {
        if values.length() != 1 { return Err(sqlInvalidArgument("expected one parameter")) }
        return Ok(values.get(0))
    }
    return Err(sqlInvalidArgument("unsupported expression: " + text))
}

static Bool memRowMatches(List<SqlValue> row, Int column, SqlValue expected) {
    return row.get(column).equals(expected)
}

static Result<SqlResult, Error> memRun(List<MemTable> tables, SqlStatement statement) {
    Result<List<SqlValue>, Error> valuesResult = memValues(statement)
    if valuesResult.isErr() { return Err(valuesResult.error()) }
    List<SqlValue> values = valuesResult.value()
    String sql = memNorm(statement.sql()).toLower()
    String lower = sql.toLower()
    if lower.startsWith("create table ") {
        String createRest = sql.substring(13, sql.length() - 13)
        Int createOpen = createRest.indexOf("(")
        Int createClose = createRest.indexOf(")", createOpen + 1)
        if createOpen <= 0 || createClose <= createOpen { return Err(sqlInvalidArgument("invalid create table")) }
        String createName = createRest.substring(0, createOpen).trim()
        if memFindTable(tables, createName) != null { return Err(sqlInvalidArgument("table exists")) }
        String createInside = createRest.substring(createOpen + 1, createClose - createOpen - 1)
        List<String> createDefs = createInside.split(",")
        List<String> createNames = []
        List<String> createTypes = []
        Int createIndex = 0
        while createIndex < createDefs.length() {
            String createDefinition = createDefs.get(createIndex).trim()
            Int createSpace = createDefinition.indexOf(" ")
            if createSpace <= 0 { return Err(sqlInvalidArgument("invalid column")) }
            createNames.push(createDefinition.substring(0, createSpace).trim())
            createTypes.push(createDefinition.substring(createSpace + 1, createDefinition.length() - createSpace - 1).trim())
            createIndex = createIndex + 1
        }
        tables.push(new MemTable(createName, createNames, createTypes))
        List<SqlColumn> createColumns = []
        List<SqlRow> createRows = []
        return Ok(memResult(createColumns, createRows, 0, false))
    }
    if lower.startsWith("insert into ") {
        String insertRest = sql.substring(12, sql.length() - 12)
        Int insertMarker = insertRest.indexOf(" values ")
        if insertMarker <= 0 { return Err(sqlInvalidArgument("invalid insert")) }
        String insertName = insertRest.substring(0, insertMarker).trim()
        MemTable? insertTableValue = memFindTable(tables, insertName)
        if insertTableValue == null { return Err(sqlInvalidArgument("unknown table")) }
        MemTable insertTable = insertTableValue as MemTable
        String insertTail = insertRest.substring(insertMarker + 8, insertRest.length() - insertMarker - 8)
        Int insertOpen = insertTail.indexOf("(")
        Int insertClose = insertTail.indexOf(")")
        if insertOpen != 0 || insertClose <= 0 { return Err(sqlInvalidArgument("invalid insert values")) }
        String insertInside = insertTail.substring(insertOpen + 1, insertClose - insertOpen - 1)
        List<String> insertParts = insertInside.split(",")
        if insertParts.length() != insertTable.columnNames.length() { return Err(sqlInvalidArgument("column count mismatch")) }
        if values.length() != insertParts.length() { return Err(sqlInvalidArgument("parameter count mismatch")) }
        List<SqlValue> insertRow = []
        Int insertIndex = 0
        while insertIndex < insertParts.length() {
            if !memIsPlaceholder(insertParts.get(insertIndex).trim()) { return Err(sqlInvalidArgument("insert only supports placeholders")) }
            insertRow.push(values.get(insertIndex))
            insertIndex = insertIndex + 1
        }
        insertTable.rows.push(insertRow)
        List<SqlColumn> insertColumns = []
        List<SqlRow> insertRows = []
        return Ok(memResult(insertColumns, insertRows, 1, false))
    }
    if lower.startsWith("select ") {
        String selectRest = sql.substring(7, sql.length() - 7)
        Int selectFrom = selectRest.indexOf(" from ")
        if selectFrom <= 0 { return Err(sqlInvalidArgument("invalid select")) }
        String selectColumnsText = selectRest.substring(0, selectFrom).trim()
        String selectTail = selectRest.substring(selectFrom + 6, selectRest.length() - selectFrom - 6).trim()
        Int selectWhere = selectTail.indexOf(" where ")
        String selectName = selectTail
        String selectCondition = ""
        if selectWhere >= 0 {
            selectName = selectTail.substring(0, selectWhere).trim()
            selectCondition = selectTail.substring(selectWhere + 7, selectTail.length() - selectWhere - 7).trim()
        }
        MemTable? selectTableValue = memFindTable(tables, selectName)
        if selectTableValue == null { return Err(sqlInvalidArgument("unknown table")) }
        MemTable selectTable = selectTableValue as MemTable
        List<String> selectSelected = []
        if selectColumnsText == "*" {
            selectSelected = selectTable.columnNames.copy()
        } else {
            List<String> selectParts = selectColumnsText.split(",")
            Int selectPartIndex = 0
            while selectPartIndex < selectParts.length() {
                selectSelected.push(selectParts.get(selectPartIndex).trim())
                selectPartIndex = selectPartIndex + 1
            }
        }
        List<Int> selectIndexes = []
        List<SqlColumn> selectColumns = []
        Int selectIndex = 0
        while selectIndex < selectSelected.length() {
            Int selectColumn = selectTable.columnIndex(selectSelected.get(selectIndex))
            if selectColumn < 0 { return Err(sqlInvalidArgument("unknown column")) }
            selectIndexes.push(selectColumn)
            selectColumns.push(new SqlColumn(selectSelected.get(selectIndex), selectTable.columnTypes.get(selectColumn), true))
            selectIndex = selectIndex + 1
        }
        Int selectWhereColumn = -1
        SqlValue selectWhereValue = SqlValue.nullValue()
        if selectCondition != "" {
            Int selectEquals = selectCondition.indexOf(" = ")
            if selectEquals <= 0 { return Err(sqlInvalidArgument("invalid where")) }
            String selectLeft = selectCondition.substring(0, selectEquals).trim()
            String selectRight = selectCondition.substring(selectEquals + 3, selectCondition.length() - selectEquals - 3).trim()
            selectWhereColumn = selectTable.columnIndex(selectLeft)
            if selectWhereColumn < 0 { return Err(sqlInvalidArgument("unknown where column")) }
            if !memIsPlaceholder(selectRight) { return Err(sqlInvalidArgument("where only supports placeholders")) }
            if values.length() != 1 { return Err(sqlInvalidArgument("where parameter mismatch")) }
            selectWhereValue = values.get(0)
        } else if values.length() != 0 {
            return Err(sqlInvalidArgument("unexpected parameters"))
        }
        List<SqlRow> selectRows = []
        Int selectRowIndex = 0
        while selectRowIndex < selectTable.rows.length() {
            List<SqlValue> selectCurrent = selectTable.rows.get(selectRowIndex)
            Bool selectInclude = true
            if selectWhereColumn >= 0 { selectInclude = memRowMatches(selectCurrent, selectWhereColumn, selectWhereValue) }
            if selectInclude {
                List<SqlValue> selectProjected = []
                Int selectColumnIndex = 0
                while selectColumnIndex < selectIndexes.length() {
                    selectProjected.push(selectCurrent.get(selectIndexes.get(selectColumnIndex)))
                    selectColumnIndex = selectColumnIndex + 1
                }
                selectRows.push(new SqlRow(selectProjected))
            }
            selectRowIndex = selectRowIndex + 1
        }
        return Ok(memResult(selectColumns, selectRows, 0, true))
    }
    if lower.startsWith("update ") {
        String updateRest = sql.substring(7, sql.length() - 7)
        Int updateSet = updateRest.indexOf(" set ")
        if updateSet <= 0 { return Err(sqlInvalidArgument("invalid update")) }
        String updateName = updateRest.substring(0, updateSet).trim()
        MemTable? updateTableValue = memFindTable(tables, updateName)
        if updateTableValue == null { return Err(sqlInvalidArgument("unknown table")) }
        MemTable updateTable = updateTableValue as MemTable
        String updateTail = updateRest.substring(updateSet + 5, updateRest.length() - updateSet - 5)
        Int updateWhere = updateTail.indexOf(" where ")
        String updateAssignment = updateTail
        String updateCondition = ""
        if updateWhere >= 0 {
            updateAssignment = updateTail.substring(0, updateWhere).trim()
            updateCondition = updateTail.substring(updateWhere + 7, updateTail.length() - updateWhere - 7).trim()
        }
        Int updateEquals = updateAssignment.indexOf(" = ")
        if updateEquals <= 0 { return Err(sqlInvalidArgument("invalid assignment")) }
        String updateColumnName = updateAssignment.substring(0, updateEquals).trim()
        Int updateColumn = updateTable.columnIndex(updateColumnName)
        if updateColumn < 0 { return Err(sqlInvalidArgument("unknown column")) }
        if !memIsPlaceholder(updateAssignment.substring(updateEquals + 3, updateAssignment.length() - updateEquals - 3).trim()) { return Err(sqlInvalidArgument("assignment only supports placeholders")) }
        Int updateWhereColumn = -1
        SqlValue updateWhereValue = SqlValue.nullValue()
        Int updateExpected = 1
        if updateCondition != "" {
            Int updateWhereEquals = updateCondition.indexOf(" = ")
            if updateWhereEquals <= 0 { return Err(sqlInvalidArgument("invalid where")) }
            updateWhereColumn = updateTable.columnIndex(updateCondition.substring(0, updateWhereEquals).trim())
            if updateWhereColumn < 0 { return Err(sqlInvalidArgument("unknown where column")) }
            if !memIsPlaceholder(updateCondition.substring(updateWhereEquals + 3, updateCondition.length() - updateWhereEquals - 3).trim()) { return Err(sqlInvalidArgument("where only supports placeholders")) }
            updateExpected = 2
        }
        if values.length() != updateExpected { return Err(sqlInvalidArgument("parameter count mismatch")) }
        Int updateAffected = 0
        Int updateRowIndex = 0
        while updateRowIndex < updateTable.rows.length() {
            List<SqlValue> updateRow = updateTable.rows.get(updateRowIndex)
            Bool updateInclude = true
            if updateWhereColumn >= 0 { updateInclude = memRowMatches(updateRow, updateWhereColumn, values.get(1)) }
            if updateInclude {
                updateRow.set(updateColumn, values.get(0))
                updateAffected = updateAffected + 1
            }
            updateRowIndex = updateRowIndex + 1
        }
        List<SqlColumn> updateColumns = []
        List<SqlRow> updateRows = []
        return Ok(memResult(updateColumns, updateRows, updateAffected as Long, false))
    }
    if lower.startsWith("delete from ") {
        String deleteRest = sql.substring(12, sql.length() - 12)
        Int deleteWhere = deleteRest.indexOf(" where ")
        String deleteName = deleteRest
        String deleteCondition = ""
        if deleteWhere >= 0 {
            deleteName = deleteRest.substring(0, deleteWhere).trim()
            deleteCondition = deleteRest.substring(deleteWhere + 7, deleteRest.length() - deleteWhere - 7).trim()
        }
        MemTable? deleteTableValue = memFindTable(tables, deleteName)
        if deleteTableValue == null { return Err(sqlInvalidArgument("unknown table")) }
        MemTable deleteTable = deleteTableValue as MemTable
        Int deleteWhereColumn = -1
        SqlValue deleteWhereValue = SqlValue.nullValue()
        if deleteCondition != "" {
            Int deleteEquals = deleteCondition.indexOf(" = ")
            if deleteEquals <= 0 { return Err(sqlInvalidArgument("invalid where")) }
            deleteWhereColumn = deleteTable.columnIndex(deleteCondition.substring(0, deleteEquals).trim())
            if deleteWhereColumn < 0 { return Err(sqlInvalidArgument("unknown where column")) }
            if !memIsPlaceholder(deleteCondition.substring(deleteEquals + 3, deleteCondition.length() - deleteEquals - 3).trim()) { return Err(sqlInvalidArgument("where only supports placeholders")) }
            if values.length() != 1 { return Err(sqlInvalidArgument("parameter count mismatch")) }
            deleteWhereValue = values.get(0)
        } else if values.length() != 0 {
            return Err(sqlInvalidArgument("unexpected parameters"))
        }
        Int deleteAffected = 0
        Int deleteRowIndex = deleteTable.rows.length() - 1
        while deleteRowIndex >= 0 {
            List<SqlValue> deleteRow = deleteTable.rows.get(deleteRowIndex)
            Bool deleteRemove = true
            if deleteWhereColumn >= 0 { deleteRemove = memRowMatches(deleteRow, deleteWhereColumn, deleteWhereValue) }
            if deleteRemove {
                deleteTable.rows.remove(deleteRowIndex)
                deleteAffected = deleteAffected + 1
            }
            deleteRowIndex = deleteRowIndex - 1
        }
        List<SqlColumn> deleteColumns = []
        List<SqlRow> deleteRows = []
        return Ok(memResult(deleteColumns, deleteRows, deleteAffected as Long, false))
    }
    return Err(sqlInvalidArgument("unsupported SQL"))
}

static SqlResult memLimit(SqlResult result, SqlOptions options) {
    if !result.isQuery() { return result }
    Int maximum = options.getMaxRows()
    if maximum <= 0 || result.rowCount() <= maximum { return result }
    List<SqlRow> limited = []
    Int index = 0
    while index < maximum {
        limited.push(result.rows().get(index))
        index = index + 1
    }
    return new SqlResult(result.columns(), limited, result.rowsAffected(), true)
}

class MemoryConnection implements SqlConnection {
    SqlDialect _dialect
    List<MemTable> _tables
    Bool _open
    Bool _transactionOpen

    MemoryConnection() {
        self._dialect = sqlDefaultDialect()
        self._tables = []
        self._open = true
        self._transactionOpen = false
    }

    SqlDialect dialect() { return self._dialect }
    Bool isOpen() { return self._open }

    List<MemTable> copyTables() { return memCopyTables(self._tables) }

    Void adoptTables(List<MemTable> tables) { self._tables = memCopyTables(tables) }

    Void endTransaction() { self._transactionOpen = false }

    Result<SqlResult, Error> execute(SqlStatement statement) {
        return self.executeWithOptions(statement, new SqlOptions())
    }

    Result<SqlResult, Error> executeWithOptions(SqlStatement statement, SqlOptions options) {
        if statement == null || options == null { throw "MemoryConnection.execute: null argument" }
        if !self._open || self._transactionOpen {
            return Err(sqlInvalidArgument("connection is closed or in transaction"))
        }
        SqlOptions snapshot = options.copy()
        if snapshot.getTimeoutMillis() < 0 || snapshot.getMaxRows() < 0 || snapshot.getFetchSize() < 0 {
            return Err(sqlInvalidArgument("invalid options"))
        }
        Result<SqlResult, Error> result = memRun(self._tables, statement)
        if result.isErr() { return result }
        return Ok(memLimit(result.value(), snapshot))
    }

    Result<SqlTransaction, Error> begin() {
        if !self._open { return Err(sqlInvalidArgument("connection is closed")) }
        if self._transactionOpen { return Err(sqlInvalidArgument("transaction already open")) }
        self._transactionOpen = true
        MemoryTransaction transaction = new MemoryTransaction(self, self.copyTables())
        SqlTransaction result = transaction
        return Ok(result)
    }

    Result<Unit, Error> close() {
        self._open = false
        self._transactionOpen = false
        return Ok()
    }
}

class MemoryTransaction implements SqlTransaction {
    MemoryConnection _connection
    List<MemTable> _tables
    Bool _open

    MemoryTransaction(MemoryConnection connection, List<MemTable> tables) {
        self._connection = connection
        self._tables = tables
        self._open = true
    }

    Result<SqlResult, Error> execute(SqlStatement statement) {
        return self.executeWithOptions(statement, new SqlOptions())
    }

    Result<SqlResult, Error> executeWithOptions(SqlStatement statement, SqlOptions options) {
        if statement == null || options == null { throw "MemoryTransaction.execute: null argument" }
        if !self._open || !self._connection.isOpen() {
            return Err(sqlInvalidArgument("transaction is closed"))
        }
        SqlOptions snapshot = options.copy()
        Result<SqlResult, Error> result = memRun(self._tables, statement)
        if result.isErr() { return result }
        return Ok(memLimit(result.value(), snapshot))
    }

    Result<Unit, Error> commit() {
        if !self._open { return Err(sqlInvalidArgument("transaction is closed")) }
        self._connection.adoptTables(self._tables)
        self._connection.endTransaction()
        self._open = false
        return Ok()
    }

    Result<Unit, Error> rollback() {
        if !self._open { return Err(sqlInvalidArgument("transaction is closed")) }
        self._connection.endTransaction()
        self._open = false
        return Ok()
    }

    Bool isOpen() { return self._open }

    Result<Unit, Error> close() {
        if self._open {
            self._connection.endTransaction()
            self._open = false
        }
        return Ok()
    }
}

class MemoryDriver implements SqlDriver {
    String name() { return "memory" }

    Result<SqlConnection, Error> open(String connectionUri, Map<String, String> openOptions) {
        if connectionUri == null || openOptions == null { throw "MemoryDriver.open: null argument" }
        Result<Uri, Error> parsed = Uri.parse(connectionUri)
        if parsed.isErr() { return Err(sqlInvalidArgument("invalid uri")) }
        String? scheme = parsed.value().scheme()
        if scheme == null {
            return Err(sqlInvalidArgument("missing scheme"))
        }
        String schemeText = scheme as String
        if schemeText.toLower() != "memory" {
            return Err(sqlInvalidArgument("unsupported scheme"))
        }
        if openOptions.has("bogus") {
            return Err(sqlInvalidArgument("unknown option: bogus"))
        }
        MemoryConnection connection = new MemoryConnection()
        SqlConnection result = connection
        return Ok(result)
    }
}
