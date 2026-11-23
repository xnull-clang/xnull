// xdk.sql — SQL value/result model and driver protocols (M6.1).
//
// Context is not implemented in core yet, so protocol signatures omit it.
// executeWithOptions is used instead of overloaded execute(statement, options).
package xdk.sql
import xdk.bytes
import xdk.errors
import xdk.math

static Error sqlError(ErrorKind kind, String message) {
    BasicError error = new BasicError(kind, message)
    return error
}

Error sqlInvalidArgument(String message) {
    return sqlError(ErrorKind.InvalidArgument, message)
}

SqlDialect sqlDefaultDialect() {
    return SqlDialect.Generic
}

enum SqlDialect {
    Postgres,
    MySql,
    Sqlite,
    Mssql,
    Oracle,
    Generic,
}

String sqlDialectName(SqlDialect dialect) {
    if dialect == SqlDialect.Postgres { return "postgres" }
    if dialect == SqlDialect.MySql { return "mysql" }
    if dialect == SqlDialect.Sqlite { return "sqlite" }
    if dialect == SqlDialect.Mssql { return "mssql" }
    if dialect == SqlDialect.Oracle { return "oracle" }
    return "generic"
}

enum SqlKind {
    Null,
    Bool,
    Int,
    Long,
    Double,
    String,
    Bytes,
}

String sqlKindName(SqlKind kind) {
    if kind == SqlKind.Null { return "null" }
    if kind == SqlKind.Bool { return "bool" }
    if kind == SqlKind.Int { return "int" }
    if kind == SqlKind.Long { return "long" }
    if kind == SqlKind.Double { return "double" }
    if kind == SqlKind.String { return "string" }
    return "bytes"
}

static Bool sqlBytesEqual(Bytes left, Bytes right) {
    if left.length() != right.length() { return false }
    Int index = 0
    while index < left.length() {
        if left.get(index) != right.get(index) { return false }
        index = index + 1
    }
    return true
}

class SqlValue {
    final SqlKind _kind
    final Bool _boolValue
    final Int _intValue
    final Long _longValue
    final Double _doubleValue
    final String _stringValue
    final Bytes _bytesValue

    private SqlValue(SqlKind kind, Bool boolValue, Int intValue, Long longValue, Double doubleValue, String stringValue, Bytes bytesValue) {
        if stringValue == null { throw "SqlValue: null string" }
        if bytesValue == null { throw "SqlValue: null bytes" }
        self._kind = kind
        self._boolValue = boolValue
        self._intValue = intValue
        self._longValue = longValue
        self._doubleValue = doubleValue
        self._stringValue = stringValue
        self._bytesValue = copy(bytesValue)
    }

    static SqlValue nullValue() {
        Bytes empty = Bytes.fromString("")
        return new SqlValue(SqlKind.Null, false, 0, 0, 0.0, "", empty)
    }

    static SqlValue ofBool(Bool value) {
        Bytes empty = Bytes.fromString("")
        return new SqlValue(SqlKind.Bool, value, 0, 0, 0.0, "", empty)
    }

    static SqlValue ofInt(Int value) {
        Bytes empty = Bytes.fromString("")
        return new SqlValue(SqlKind.Int, false, value, 0, 0.0, "", empty)
    }

    static SqlValue ofLong(Long value) {
        Bytes empty = Bytes.fromString("")
        return new SqlValue(SqlKind.Long, false, 0, value, 0.0, "", empty)
    }

    static SqlValue ofDouble(Double value) {
        Bytes empty = Bytes.fromString("")
        return new SqlValue(SqlKind.Double, false, 0, 0, value, "", empty)
    }

    static SqlValue ofString(String value) {
        if value == null { throw "SqlValue.ofString: null value" }
        Bytes empty = Bytes.fromString("")
        return new SqlValue(SqlKind.String, false, 0, 0, 0.0, value, empty)
    }

    static SqlValue ofBytes(Bytes value) {
        if value == null { throw "SqlValue.ofBytes: null value" }
        return new SqlValue(SqlKind.Bytes, false, 0, 0, 0.0, "", value)
    }

    SqlKind kind() { return self._kind }
    Bool isNull() { return self._kind == SqlKind.Null }

    Result<Bool, Error> asBool() {
        if self._kind != SqlKind.Bool { return Err(sqlError(ErrorKind.InvalidArgument, "SqlValue.asBool: kind=" + sqlKindName(self._kind))) }
        return Ok(self._boolValue)
    }

    Result<Int, Error> asInt() {
        if self._kind != SqlKind.Int { return Err(sqlError(ErrorKind.InvalidArgument, "SqlValue.asInt: kind=" + sqlKindName(self._kind))) }
        return Ok(self._intValue)
    }

    Result<Long, Error> asLong() {
        if self._kind != SqlKind.Long { return Err(sqlError(ErrorKind.InvalidArgument, "SqlValue.asLong: kind=" + sqlKindName(self._kind))) }
        return Ok(self._longValue)
    }

    Result<Double, Error> asDouble() {
        if self._kind != SqlKind.Double { return Err(sqlError(ErrorKind.InvalidArgument, "SqlValue.asDouble: kind=" + sqlKindName(self._kind))) }
        return Ok(self._doubleValue)
    }

    Result<String, Error> asString() {
        if self._kind != SqlKind.String { return Err(sqlError(ErrorKind.InvalidArgument, "SqlValue.asString: kind=" + sqlKindName(self._kind))) }
        return Ok(self._stringValue)
    }

    Result<Bytes, Error> asBytes() {
        if self._kind != SqlKind.Bytes { return Err(sqlError(ErrorKind.InvalidArgument, "SqlValue.asBytes: kind=" + sqlKindName(self._kind))) }
        return Ok(copy(self._bytesValue))
    }

    Bool equals(SqlValue other) {
        if other == null { return false }
        if self._kind != other._kind { return false }
        if self._kind == SqlKind.Null { return true }
        if self._kind == SqlKind.Bool { return self._boolValue == other._boolValue }
        if self._kind == SqlKind.Int { return self._intValue == other._intValue }
        if self._kind == SqlKind.Long { return self._longValue == other._longValue }
        if self._kind == SqlKind.Double {
            if isNaN(self._doubleValue) && isNaN(other._doubleValue) { return true }
            return self._doubleValue == other._doubleValue
        }
        if self._kind == SqlKind.String { return self._stringValue == other._stringValue }
        return sqlBytesEqual(self._bytesValue, other._bytesValue)
    }

    String describe() { return "SqlValue(kind=" + sqlKindName(self._kind) + ")" }
}

class SqlParameter {
    final Int _parameterIndex
    final String _name
    final SqlValue _value

    private SqlParameter(Int parameterIndex, String name, SqlValue value) {
        if name == null { throw "SqlParameter: null name" }
        if value == null { throw "SqlParameter: null value" }
        if parameterIndex < 0 { throw "SqlParameter: negative index" }
        Bool indexed = parameterIndex > 0
        Bool named = name.length() > 0
        if indexed == named { throw "SqlParameter: exactly one of index/name is required" }
        self._parameterIndex = parameterIndex
        self._name = name
        self._value = value
    }

    static SqlParameter indexed(Int parameterIndex, SqlValue value) {
        if parameterIndex < 1 { throw "SqlParameter.indexed: parameterIndex < 1" }
        return new SqlParameter(parameterIndex, "", value)
    }

    static SqlParameter named(String name, SqlValue value) {
        if name == null || name.trim() == "" { throw "SqlParameter.named: empty name" }
        return new SqlParameter(0, name, value)
    }

    Int parameterIndex() { return self._parameterIndex }
    String name() { return self._name }
    SqlValue value() { return self._value }
    Bool isIndexed() { return self._parameterIndex > 0 }
    Bool isNamed() { return self._name.length() > 0 }

    Bool equals(SqlParameter other) {
        if other == null { return false }
        return self._parameterIndex == other.parameterIndex() && self._name == other.name() && self._value.equals(other.value())
    }

    String describe() {
        String mode = ""
        if self.isIndexed() { mode = "indexed=" + str(self._parameterIndex) }
        if self.isNamed() { mode = "named=" + self._name }
        return "SqlParameter(" + mode + " kind=" + sqlKindName(self._value.kind()) + ")"
    }
}

class SqlColumn {
    final String _name
    final String _typeName
    final Bool _isNullable

    SqlColumn(String name, String typeName, Bool isNullable) {
        if name == null || name == "" { throw "SqlColumn: empty name" }
        if typeName == null || typeName == "" { throw "SqlColumn: empty typeName" }
        self._name = name
        self._typeName = typeName
        self._isNullable = isNullable
    }

    String name() { return self._name }
    String typeName() { return self._typeName }
    Bool isNullable() { return self._isNullable }

    Bool equals(SqlColumn other) {
        if other == null { return false }
        return self._name == other.name() && self._typeName == other.typeName() && self._isNullable == other.isNullable()
    }

    String describe() {
        String nullability = "not null"
        if self._isNullable { nullability = "nullable" }
        return self._name + ":" + self._typeName + " " + nullability
    }
}

class SqlRow {
    final List<SqlValue> _values

    SqlRow(List<SqlValue> values) {
        if values == null { throw "SqlRow: null values" }
        List<SqlValue> copied = []
        Int index = 0
        while index < values.length() {
            if values.get(index) == null { throw "SqlRow: null value at " + str(index) }
            copied.push(values.get(index))
            index = index + 1
        }
        self._values = copied
    }

    Int length() { return self._values.length() }

    SqlValue get(Int columnIndex) {
        if columnIndex < 0 || columnIndex >= self._values.length() { throw "SqlRow.get: columnIndex out of range" }
        return self._values.get(columnIndex)
    }

    SqlValue? tryGet(Int columnIndex) {
        if columnIndex < 0 || columnIndex >= self._values.length() { return null }
        return self._values.get(columnIndex)
    }

    Bool equals(SqlRow other) {
        if other == null { return false }
        if self._values.length() != other.length() { return false }
        Int index = 0
        while index < self._values.length() {
            if !self._values.get(index).equals(other.get(index)) { return false }
            index = index + 1
        }
        return true
    }

    String describe() { return "SqlRow(values=" + str(self._values.length()) + ")" }
}

class SqlStatement {
    final String _sql
    List<SqlParameter> _parameters

    SqlStatement(String sqlText) {
        if sqlText == null { throw "SqlStatement: null sql" }
        if sqlText.trim() == "" { throw "SqlStatement: empty sql" }
        self._sql = sqlText
        self._parameters = []
    }

    static SqlStatement fromParameters(String sqlText, List<SqlParameter> parameterList) {
        if parameterList == null { throw "SqlStatement: null parameters" }
        SqlStatement result = new SqlStatement(sqlText)
        List<SqlParameter> copied = []
        Bool hasIndexed = false
        Bool hasNamed = false
        Int index = 0
        while index < parameterList.length() {
            SqlParameter parameter = parameterList.get(index)
            if parameter == null { throw "SqlStatement: null parameter" }
            if parameter.isIndexed() {
                hasIndexed = true
                if parameter.parameterIndex() != index + 1 { throw "SqlStatement: non-contiguous index" }
            }
            if parameter.isNamed() {
                hasNamed = true
                Int scan = 0
                while scan < index {
                    SqlParameter previous = parameterList.get(scan)
                    if previous.isNamed() && previous.name() == parameter.name() {
                        throw "SqlStatement: duplicate parameter name"
                    }
                    scan = scan + 1
                }
            }
            copied.push(parameter)
            index = index + 1
        }
        if hasIndexed && hasNamed { throw "SqlStatement: mixed parameter styles" }
        result._parameters = copied
        return result
    }

    String sql() { return self._sql }
    List<SqlParameter> parameters() { return self._parameters.copy() }
    Int parameterCount() { return self._parameters.length() }

    Bool isNamedParameters() {
        if self._parameters.length() == 0 { return false }
        return self._parameters.get(0).isNamed()
    }

    SqlStatement bind(SqlValue value) {
        if value == null { throw "SqlStatement.bind: null value" }
        if self.isNamedParameters() { throw "SqlStatement.bind: named statement" }
        List<SqlParameter> next = self._parameters.copy()
        SqlParameter parameter = SqlParameter.indexed(next.length() + 1, value)
        next.push(parameter)
        return SqlStatement.fromParameters(self._sql, next)
    }

    SqlStatement withParameter(SqlParameter parameter) {
        if parameter == null { throw "SqlStatement.withParameter: null parameter" }
        List<SqlParameter> next = self._parameters.copy()
        if self._parameters.length() == 0 {
            if parameter.isIndexed() && parameter.parameterIndex() != 1 {
                throw "SqlStatement.withParameter: first index must be 1"
            }
        } else {
            Bool currentNamed = self._parameters.get(0).isNamed()
            if currentNamed != parameter.isNamed() { throw "SqlStatement.withParameter: mixed styles" }
            if parameter.isIndexed() && parameter.parameterIndex() != next.length() + 1 {
                throw "SqlStatement.withParameter: non-contiguous index"
            }
            if parameter.isNamed() {
                Int scan = 0
                while scan < next.length() {
                    if next.get(scan).isNamed() && next.get(scan).name() == parameter.name() {
                        throw "SqlStatement.withParameter: duplicate name"
                    }
                    scan = scan + 1
                }
            }
        }
        next.push(parameter)
        return SqlStatement.fromParameters(self._sql, next)
    }

    SqlStatement clear() { return new SqlStatement(self._sql) }

    Bool equals(SqlStatement other) {
        if other == null { return false }
        if self._sql != other.sql() { return false }
        List<SqlParameter> otherParameters = other.parameters()
        if self._parameters.length() != otherParameters.length() { return false }
        Int index = 0
        while index < self._parameters.length() {
            if !self._parameters.get(index).equals(otherParameters.get(index)) { return false }
            index = index + 1
        }
        return true
    }

    String describe() {
        String style = "none"
        if self.isNamedParameters() { style = "named" }
        else if self._parameters.length() > 0 { style = "indexed" }
        return "SqlStatement(sqlLength=" + str(self._sql.length()) + " parameters=" + str(self._parameters.length()) + " style=" + style + ")"
    }
}

class SqlResult {
    final List<SqlColumn> _columns
    final List<SqlRow> _rows
    final Long _rowsAffected
    final Bool _isQuery

    SqlResult(List<SqlColumn> columns, List<SqlRow> rows, Long rowsAffected, Bool isQuery) {
        if columns == null || rows == null { throw "SqlResult: null list" }
        if rowsAffected < 0 { throw "SqlResult: negative rowsAffected" }
        List<SqlColumn> columnCopy = columns.copy()
        List<SqlRow> rowCopy = rows.copy()
        Int columnIndex = 0
        while columnIndex < columnCopy.length() {
            if columnCopy.get(columnIndex) == null { throw "SqlResult: null column" }
            columnIndex = columnIndex + 1
        }
        Int rowIndex = 0
        while rowIndex < rowCopy.length() {
            SqlRow row = rowCopy.get(rowIndex)
            if row == null { throw "SqlResult: null row" }
            if row.length() != columnCopy.length() { throw "SqlResult: row length mismatch" }
            rowIndex = rowIndex + 1
        }
        if isQuery && columnCopy.length() == 0 { throw "SqlResult: query without columns" }
        if !isQuery && (columnCopy.length() > 0 || rowCopy.length() > 0) { throw "SqlResult: non-query with columns or rows" }
        self._columns = columnCopy
        self._rows = rowCopy
        self._rowsAffected = rowsAffected
        self._isQuery = isQuery
    }

    List<SqlColumn> columns() { return self._columns.copy() }
    Int columnCount() { return self._columns.length() }
    List<SqlRow> rows() { return self._rows.copy() }
    Int rowCount() { return self._rows.length() }
    Long rowsAffected() { return self._rowsAffected }
    Bool isQuery() { return self._isQuery }

    Bool equals(SqlResult other) {
        if other == null { return false }
        if self._rowsAffected != other.rowsAffected() { return false }
        if self._isQuery != other.isQuery() { return false }
        List<SqlColumn> otherColumns = other.columns()
        if self._columns.length() != otherColumns.length() { return false }
        Int index = 0
        while index < self._columns.length() {
            if !self._columns.get(index).equals(otherColumns.get(index)) { return false }
            index = index + 1
        }
        List<SqlRow> otherRows = other.rows()
        if self._rows.length() != otherRows.length() { return false }
        index = 0
        while index < self._rows.length() {
            if !self._rows.get(index).equals(otherRows.get(index)) { return false }
            index = index + 1
        }
        return true
    }

    String describe() {
        if self._isQuery {
            return "SqlResult(query=true columns=" + str(self._columns.length()) + " rows=" + str(self._rows.length()) + " affected=" + str(self._rowsAffected) + ")"
        }
        return "SqlResult(query=false affected=" + str(self._rowsAffected) + ")"
    }
}

class SqlOptions {
    Long _timeoutMillis
    Int _maxRows
    Int _fetchSize

    SqlOptions() {
        self._timeoutMillis = 0
        self._maxRows = 0
        self._fetchSize = 0
    }

    SqlOptions timeoutMillis(Long value) {
        if value < 0 { throw "SqlOptions.timeoutMillis: negative" }
        self._timeoutMillis = value
        return self
    }

    SqlOptions maxRows(Int value) {
        if value < 0 { throw "SqlOptions.maxRows: negative" }
        self._maxRows = value
        return self
    }

    SqlOptions fetchSize(Int value) {
        if value < 0 { throw "SqlOptions.fetchSize: negative" }
        self._fetchSize = value
        return self
    }

    Long getTimeoutMillis() { return self._timeoutMillis }
    Int getMaxRows() { return self._maxRows }
    Int getFetchSize() { return self._fetchSize }

    SqlOptions copy() {
        SqlOptions result = new SqlOptions()
        result._timeoutMillis = self._timeoutMillis
        result._maxRows = self._maxRows
        result._fetchSize = self._fetchSize
        return result
    }

    String describe() {
        return "SqlOptions(timeoutMillis=" + str(self._timeoutMillis) + " maxRows=" + str(self._maxRows) + " fetchSize=" + str(self._fetchSize) + ")"
    }
}

protocol SqlDriver {
    String name();
    Result<SqlConnection, Error> open(String connectionUri, Map<String, String> openOptions);
}

protocol SqlConnection {
    SqlDialect dialect();
    Result<SqlResult, Error> execute(SqlStatement statement);
    Result<SqlResult, Error> executeWithOptions(SqlStatement statement, SqlOptions options);
    Result<SqlTransaction, Error> begin();
    Bool isOpen();
    Result<Unit, Error> close();
}

protocol SqlTransaction {
    Result<SqlResult, Error> execute(SqlStatement statement);
    Result<SqlResult, Error> executeWithOptions(SqlStatement statement, SqlOptions options);
    Result<Unit, Error> commit();
    Result<Unit, Error> rollback();
    Bool isOpen();
    Result<Unit, Error> close();
}
