// xdk.db — database toolbox value types and protocols (M6.4a).
package xdk.db
import xdk.bytes
import xdk.errors
import xdk.runtime
import xdk.sql
import xdk.text
import xdk.time

String isolationOpenOptionKey() {
    return "xdk.isolation"
}

enum IsolationLevel {
    Unknown,
    ReadUncommitted,
    ReadCommitted,
    RepeatableRead,
    Serializable,
}

String isolationLevelName(IsolationLevel level) {
    if level == IsolationLevel.Unknown { return "unknown" }
    if level == IsolationLevel.ReadUncommitted { return "read_uncommitted" }
    if level == IsolationLevel.ReadCommitted { return "read_committed" }
    if level == IsolationLevel.RepeatableRead { return "repeatable_read" }
    return "serializable"
}

IsolationLevel? isolationLevelFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower().replace(" ", "_")
    if normalized == "read_uncommitted" { return IsolationLevel.ReadUncommitted }
    if normalized == "read_committed" { return IsolationLevel.ReadCommitted }
    if normalized == "repeatable_read" { return IsolationLevel.RepeatableRead }
    if normalized == "serializable" { return IsolationLevel.Serializable }
    return null
}

static Bool dbAsciiLetter(String character) {
    return "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".indexOf(character) >= 0
}

static Bool dbAsciiDigit(String character) {
    return "0123456789".indexOf(character) >= 0
}

static Bool dbValidName(String name) {
    if name == null || name.length() == 0 || name.length() > 64 { return false }
    if !dbAsciiLetter(name.substring(0, 1)) { return false }
    Int index = 0
    while index < name.length() {
        String character = name.substring(index, 1)
        if !dbAsciiLetter(character) && !dbAsciiDigit(character) && character != "_" && character != "-" {
            return false
        }
        index = index + 1
    }
    return true
}

static Bool dbValidOptionKey(String key) {
    if key == null || key.length() == 0 || key.length() > 128 { return false }
    Int index = 0
    while index < key.length() {
        String character = key.substring(index, 1)
        if character == " " || character == "\t" || character == "\n" || character == "\r" {
            return false
        }
        index = index + 1
    }
    return true
}

static Bool dbValidOptionValue(String value) {
    if value == null || value.length() > 4096 { return false }
    if value.indexOf("\n") >= 0 || value.indexOf("\r") >= 0 || value.indexOf("\t") >= 0 { return false }
    return true
}

static Map<String, String> dbCopyOptions(Map<String, String> options) {
    Map<String, String> result = [:]
    List<String> keys = options.keys()
    Int index = 0
    while index < keys.length() {
        String key = keys.get(index)
        result.put(key, options.getOr(key, ""))
        index = index + 1
    }
    return result
}

class DatabaseConfig {
    final String _name
    final String _connectionUri
    final Map<String, String> _openOptions
    final IsolationLevel? _isolationLevel
    final Int _minimumIdle
    final Int _maximumPoolSize
    final Long _acquireTimeoutMillis
    final Long _idleTimeoutMillis
    final Long _maximumLifetimeMillis
    final Long _validationTimeoutMillis
    final Long _leakDetectionThresholdMillis
    final Bool _failFast
    final Bool _validateOnAcquire
    final SqlStatement? _validationStatement

    DatabaseConfig(String name, String connectionUri, Map<String, String> openOptions,
                   IsolationLevel? isolationLevel, Int minimumIdle, Int maximumPoolSize,
                   Long acquireTimeoutMillis, Long idleTimeoutMillis, Long maximumLifetimeMillis,
                   Long validationTimeoutMillis, Long leakDetectionThresholdMillis,
                   Bool failFast, Bool validateOnAcquire, SqlStatement? validationStatement) {
        if !dbValidName(name) { throw "DatabaseConfig: invalid name" }
        if connectionUri == null || connectionUri.trim() == "" { throw "DatabaseConfig: empty connectionUri" }
        if openOptions == null { throw "DatabaseConfig: null openOptions" }
        if maximumPoolSize < 1 { throw "DatabaseConfig: maximumPoolSize < 1" }
        if minimumIdle < 0 || minimumIdle > maximumPoolSize { throw "DatabaseConfig: invalid minimumIdle" }
        if acquireTimeoutMillis < 0 || idleTimeoutMillis < 0 || maximumLifetimeMillis < 0 || validationTimeoutMillis < 0 {
            throw "DatabaseConfig: negative timeout"
        }
        if acquireTimeoutMillis > 0 && validationTimeoutMillis > 0 && validationTimeoutMillis >= acquireTimeoutMillis {
            throw "DatabaseConfig: validationTimeout must be less than acquireTimeout"
        }
        if leakDetectionThresholdMillis < 0 { throw "DatabaseConfig: negative leak threshold" }
        if leakDetectionThresholdMillis > 0 && leakDetectionThresholdMillis < 1000 {
            throw "DatabaseConfig: leak threshold below 1000"
        }
        Map<String, String> optionCopy = [:]
        List<String> keys = openOptions.keys()
        Int index = 0
        while index < keys.length() {
            String key = keys.get(index)
            String value = openOptions.getOr(key, "")
            if !dbValidOptionKey(key) { throw "DatabaseConfig: invalid option key" }
            if key == isolationOpenOptionKey() { throw "DatabaseConfig: reserved isolation option" }
            if !dbValidOptionValue(value) { throw "DatabaseConfig: invalid option value" }
            optionCopy.put(key, value)
            index = index + 1
        }
        self._name = name
        self._connectionUri = connectionUri
        self._openOptions = optionCopy
        self._isolationLevel = isolationLevel
        self._minimumIdle = minimumIdle
        self._maximumPoolSize = maximumPoolSize
        self._acquireTimeoutMillis = acquireTimeoutMillis
        self._idleTimeoutMillis = idleTimeoutMillis
        self._maximumLifetimeMillis = maximumLifetimeMillis
        self._validationTimeoutMillis = validationTimeoutMillis
        self._leakDetectionThresholdMillis = leakDetectionThresholdMillis
        self._failFast = failFast
        self._validateOnAcquire = validateOnAcquire
        self._validationStatement = validationStatement
    }

    static DatabaseConfig of(String name, String connectionUri) {
        Map<String, String> options = [:]
        return new DatabaseConfig(name, connectionUri, options, null, 0, 10,
            30000, 600000, 1800000, 5000, 0, true, true, null)
    }

    String name() { return self._name }
    String connectionUri() { return self._connectionUri }
    Map<String, String> openOptions() { return dbCopyOptions(self._openOptions) }
    IsolationLevel? isolationLevel() { return self._isolationLevel }
    Int minimumIdle() { return self._minimumIdle }
    Int maximumPoolSize() { return self._maximumPoolSize }
    Long acquireTimeoutMillis() { return self._acquireTimeoutMillis }
    Long idleTimeoutMillis() { return self._idleTimeoutMillis }
    Long maximumLifetimeMillis() { return self._maximumLifetimeMillis }
    Long validationTimeoutMillis() { return self._validationTimeoutMillis }
    Long leakDetectionThresholdMillis() { return self._leakDetectionThresholdMillis }
    Bool failFast() { return self._failFast }
    Bool validateOnAcquire() { return self._validateOnAcquire }
    SqlStatement? validationStatement() { return self._validationStatement }

    DatabaseConfig withOpenOptions(Map<String, String> options) {
        return new DatabaseConfig(self._name, self._connectionUri, options,
            self._isolationLevel, self._minimumIdle, self._maximumPoolSize,
            self._acquireTimeoutMillis, self._idleTimeoutMillis, self._maximumLifetimeMillis,
            self._validationTimeoutMillis, self._leakDetectionThresholdMillis,
            self._failFast, self._validateOnAcquire, self._validationStatement)
    }

    DatabaseConfig withOpenOption(String key, String value) {
        if key == null || value == null { throw "DatabaseConfig.withOpenOption: null" }
        Map<String, String> next = dbCopyOptions(self._openOptions)
        next.put(key, value)
        return self.withOpenOptions(next)
    }

    DatabaseConfig withIsolationLevel(IsolationLevel? level) {
        return new DatabaseConfig(self._name, self._connectionUri, self._openOptions,
            level, self._minimumIdle, self._maximumPoolSize,
            self._acquireTimeoutMillis, self._idleTimeoutMillis, self._maximumLifetimeMillis,
            self._validationTimeoutMillis, self._leakDetectionThresholdMillis,
            self._failFast, self._validateOnAcquire, self._validationStatement)
    }

    DatabaseConfig withPoolSize(Int minimumIdle, Int maximumPoolSize) {
        return new DatabaseConfig(self._name, self._connectionUri, self._openOptions,
            self._isolationLevel, minimumIdle, maximumPoolSize,
            self._acquireTimeoutMillis, self._idleTimeoutMillis, self._maximumLifetimeMillis,
            self._validationTimeoutMillis, self._leakDetectionThresholdMillis,
            self._failFast, self._validateOnAcquire, self._validationStatement)
    }

    DatabaseConfig withAcquireTimeoutMillis(Long value) {
        return new DatabaseConfig(self._name, self._connectionUri, self._openOptions,
            self._isolationLevel, self._minimumIdle, self._maximumPoolSize,
            value, self._idleTimeoutMillis, self._maximumLifetimeMillis,
            self._validationTimeoutMillis, self._leakDetectionThresholdMillis,
            self._failFast, self._validateOnAcquire, self._validationStatement)
    }

    DatabaseConfig withIdleTimeoutMillis(Long value) {
        return new DatabaseConfig(self._name, self._connectionUri, self._openOptions,
            self._isolationLevel, self._minimumIdle, self._maximumPoolSize,
            self._acquireTimeoutMillis, value, self._maximumLifetimeMillis,
            self._validationTimeoutMillis, self._leakDetectionThresholdMillis,
            self._failFast, self._validateOnAcquire, self._validationStatement)
    }

    DatabaseConfig withMaximumLifetimeMillis(Long value) {
        return new DatabaseConfig(self._name, self._connectionUri, self._openOptions,
            self._isolationLevel, self._minimumIdle, self._maximumPoolSize,
            self._acquireTimeoutMillis, self._idleTimeoutMillis, value,
            self._validationTimeoutMillis, self._leakDetectionThresholdMillis,
            self._failFast, self._validateOnAcquire, self._validationStatement)
    }

    DatabaseConfig withValidationTimeoutMillis(Long value) {
        return new DatabaseConfig(self._name, self._connectionUri, self._openOptions,
            self._isolationLevel, self._minimumIdle, self._maximumPoolSize,
            self._acquireTimeoutMillis, self._idleTimeoutMillis, self._maximumLifetimeMillis,
            value, self._leakDetectionThresholdMillis,
            self._failFast, self._validateOnAcquire, self._validationStatement)
    }

    DatabaseConfig withLeakDetectionThresholdMillis(Long value) {
        return new DatabaseConfig(self._name, self._connectionUri, self._openOptions,
            self._isolationLevel, self._minimumIdle, self._maximumPoolSize,
            self._acquireTimeoutMillis, self._idleTimeoutMillis, self._maximumLifetimeMillis,
            self._validationTimeoutMillis, value,
            self._failFast, self._validateOnAcquire, self._validationStatement)
    }

    DatabaseConfig withFailFast(Bool value) {
        return new DatabaseConfig(self._name, self._connectionUri, self._openOptions,
            self._isolationLevel, self._minimumIdle, self._maximumPoolSize,
            self._acquireTimeoutMillis, self._idleTimeoutMillis, self._maximumLifetimeMillis,
            self._validationTimeoutMillis, self._leakDetectionThresholdMillis,
            value, self._validateOnAcquire, self._validationStatement)
    }

    DatabaseConfig withValidateOnAcquire(Bool value) {
        return new DatabaseConfig(self._name, self._connectionUri, self._openOptions,
            self._isolationLevel, self._minimumIdle, self._maximumPoolSize,
            self._acquireTimeoutMillis, self._idleTimeoutMillis, self._maximumLifetimeMillis,
            self._validationTimeoutMillis, self._leakDetectionThresholdMillis,
            self._failFast, value, self._validationStatement)
    }

    DatabaseConfig withValidationStatement(SqlStatement? statement) {
        return new DatabaseConfig(self._name, self._connectionUri, self._openOptions,
            self._isolationLevel, self._minimumIdle, self._maximumPoolSize,
            self._acquireTimeoutMillis, self._idleTimeoutMillis, self._maximumLifetimeMillis,
            self._validationTimeoutMillis, self._leakDetectionThresholdMillis,
            self._failFast, self._validateOnAcquire, statement)
    }

    DatabaseConfig copy() {
        return new DatabaseConfig(self._name, self._connectionUri, self._openOptions,
            self._isolationLevel, self._minimumIdle, self._maximumPoolSize,
            self._acquireTimeoutMillis, self._idleTimeoutMillis, self._maximumLifetimeMillis,
            self._validationTimeoutMillis, self._leakDetectionThresholdMillis,
            self._failFast, self._validateOnAcquire, self._validationStatement)
    }

    String describe() {
        String isolation = "driver-default"
        if self._isolationLevel != null {
            IsolationLevel level = self._isolationLevel as IsolationLevel
            isolation = isolationLevelName(level)
        }
        String validation = "isOpen"
        if self._validationStatement != null { validation = "statement" }
        return "DatabaseConfig(name=" + self._name +
            " pool=" + str(self._maximumPoolSize) +
            " idle=" + str(self._minimumIdle) +
            " acquireMs=" + str(self._acquireTimeoutMillis) +
            " idleMs=" + str(self._idleTimeoutMillis) +
            " lifeMs=" + str(self._maximumLifetimeMillis) +
            " isolation=" + isolation +
            " failFast=" + str(self._failFast) +
            " validate=" + str(self._validateOnAcquire) +
            " validation=" + validation +
            " options=" + str(self._openOptions.keys().length()) +
            " uri=<redacted>)"
    }
}

class DatabasePoolStats {
    final String _name
    final Int _maximumConnections
    final Int _minimumIdle
    final Int _totalConnections
    final Int _idleConnections
    final Int _activeConnections
    final Int _openingConnections
    final Int _waitingRequests
    final Long _createdCount
    final Long _closedCount
    final Long _acquireCount
    final Long _acquireTimeoutCount
    final Long _validationFailureCount
    final Long _leakedLeaseCount
    final Long _waitCount
    final Long _waitMillisTotal
    final Long _maximumWaitMillis
    final Long _timestampMono
    final Bool _isClosed

    DatabasePoolStats(String name, Int maximumConnections, Int minimumIdle,
                      Int totalConnections, Int idleConnections, Int activeConnections,
                      Int openingConnections, Int waitingRequests,
                      Long createdCount, Long closedCount, Long acquireCount,
                      Long acquireTimeoutCount, Long validationFailureCount,
                      Long leakedLeaseCount, Long waitCount, Long waitMillisTotal,
                      Long maximumWaitMillis, Long timestampMono, Bool isClosed) {
        if name == null || name == "" { throw "DatabasePoolStats: empty name" }
        if maximumConnections < 1 { throw "DatabasePoolStats: maximumConnections < 1" }
        if minimumIdle < 0 || minimumIdle > maximumConnections { throw "DatabasePoolStats: invalid minimumIdle" }
        if idleConnections < 0 || activeConnections < 0 || openingConnections < 0 || waitingRequests < 0 {
            throw "DatabasePoolStats: negative gauge"
        }
        if totalConnections != idleConnections + activeConnections + openingConnections {
            throw "DatabasePoolStats: inconsistent total"
        }
        if totalConnections > maximumConnections { throw "DatabasePoolStats: total above maximum" }
        if createdCount < 0 || closedCount < 0 || acquireCount < 0 || acquireTimeoutCount < 0 ||
           validationFailureCount < 0 || leakedLeaseCount < 0 || waitCount < 0 ||
           waitMillisTotal < 0 || maximumWaitMillis < 0 {
            throw "DatabasePoolStats: negative counter"
        }
        if maximumWaitMillis > waitMillisTotal { throw "DatabasePoolStats: maximum wait above total" }
        if timestampMono < 0 { throw "DatabasePoolStats: negative timestamp" }
        self._name = name
        self._maximumConnections = maximumConnections
        self._minimumIdle = minimumIdle
        self._totalConnections = totalConnections
        self._idleConnections = idleConnections
        self._activeConnections = activeConnections
        self._openingConnections = openingConnections
        self._waitingRequests = waitingRequests
        self._createdCount = createdCount
        self._closedCount = closedCount
        self._acquireCount = acquireCount
        self._acquireTimeoutCount = acquireTimeoutCount
        self._validationFailureCount = validationFailureCount
        self._leakedLeaseCount = leakedLeaseCount
        self._waitCount = waitCount
        self._waitMillisTotal = waitMillisTotal
        self._maximumWaitMillis = maximumWaitMillis
        self._timestampMono = timestampMono
        self._isClosed = isClosed
    }

    String name() { return self._name }
    Int maximumConnections() { return self._maximumConnections }
    Int minimumIdle() { return self._minimumIdle }
    Int totalConnections() { return self._totalConnections }
    Int idleConnections() { return self._idleConnections }
    Int activeConnections() { return self._activeConnections }
    Int openingConnections() { return self._openingConnections }
    Int waitingRequests() { return self._waitingRequests }
    Long createdCount() { return self._createdCount }
    Long closedCount() { return self._closedCount }
    Long acquireCount() { return self._acquireCount }
    Long acquireTimeoutCount() { return self._acquireTimeoutCount }
    Long validationFailureCount() { return self._validationFailureCount }
    Long leakedLeaseCount() { return self._leakedLeaseCount }
    Long waitCount() { return self._waitCount }
    Long waitMillisTotal() { return self._waitMillisTotal }
    Long maximumWaitMillis() { return self._maximumWaitMillis }
    Long timestampMono() { return self._timestampMono }
    Bool isClosed() { return self._isClosed }

    Double utilization() {
        Double used = (self._activeConnections + self._openingConnections) as Double
        Double maximum = self._maximumConnections as Double
        Double ratio = used / maximum
        if ratio < 0.0 { return 0.0 }
        if ratio > 1.0 { return 1.0 }
        return ratio
    }

    Double averageWaitMillis() {
        if self._waitCount == 0 { return 0.0 }
        return (self._waitMillisTotal as Double) / (self._waitCount as Double)
    }

    Bool isSaturated() {
        return self._totalConnections >= self._maximumConnections && self._waitingRequests > 0
    }

    Bool isIdle() {
        return self._activeConnections == 0 && self._waitingRequests == 0
    }

    DatabasePoolStats copy() {
        return new DatabasePoolStats(self._name, self._maximumConnections, self._minimumIdle,
            self._totalConnections, self._idleConnections, self._activeConnections,
            self._openingConnections, self._waitingRequests, self._createdCount, self._closedCount,
            self._acquireCount, self._acquireTimeoutCount, self._validationFailureCount,
            self._leakedLeaseCount, self._waitCount, self._waitMillisTotal,
            self._maximumWaitMillis, self._timestampMono, self._isClosed)
    }

    Bool equals(DatabasePoolStats other) {
        if other == null { return false }
        return self._name == other.name() &&
            self._maximumConnections == other.maximumConnections() &&
            self._minimumIdle == other.minimumIdle() &&
            self._totalConnections == other.totalConnections() &&
            self._idleConnections == other.idleConnections() &&
            self._activeConnections == other.activeConnections() &&
            self._openingConnections == other.openingConnections() &&
            self._waitingRequests == other.waitingRequests() &&
            self._createdCount == other.createdCount() &&
            self._closedCount == other.closedCount() &&
            self._acquireCount == other.acquireCount() &&
            self._acquireTimeoutCount == other.acquireTimeoutCount() &&
            self._validationFailureCount == other.validationFailureCount() &&
            self._leakedLeaseCount == other.leakedLeaseCount() &&
            self._waitCount == other.waitCount() &&
            self._waitMillisTotal == other.waitMillisTotal() &&
            self._maximumWaitMillis == other.maximumWaitMillis() &&
            self._timestampMono == other.timestampMono() &&
            self._isClosed == other.isClosed()
    }

    String describe() {
        return "DatabasePoolStats(name=" + self._name +
            " total=" + str(self._totalConnections) +
            " idle=" + str(self._idleConnections) +
            " active=" + str(self._activeConnections) +
            " opening=" + str(self._openingConnections) +
            " waiting=" + str(self._waitingRequests) +
            " max=" + str(self._maximumConnections) +
            " acquired=" + str(self._acquireCount) +
            " timeouts=" + str(self._acquireTimeoutCount) +
            " validationFailures=" + str(self._validationFailureCount) +
            " leaks=" + str(self._leakedLeaseCount) +
            " closed=" + str(self._isClosed) + ")"
    }
}

class DbBatch {
    final List<SqlStatement> _statements

    DbBatch() {
        self._statements = []
    }

    static DbBatch fromStatements(List<SqlStatement> statements) {
        if statements == null { throw "DbBatch: null statements" }
        DbBatch batch = new DbBatch()
        Int index = 0
        while index < statements.length() {
            SqlStatement statement = statements.get(index)
            if statement == null { throw "DbBatch: null statement at " + str(index) }
            batch._statements.push(statement)
            index = index + 1
        }
        return batch
    }

    DbBatch add(SqlStatement statement) {
        if statement == null { throw "DbBatch.add: null statement" }
        self._statements.push(statement)
        return self
    }

    DbBatch addAll(List<SqlStatement> statements) {
        if statements == null { throw "DbBatch.addAll: null statements" }
        List<SqlStatement> copied = []
        Int index = 0
        while index < statements.length() {
            SqlStatement statement = statements.get(index)
            if statement == null { throw "DbBatch.addAll: null statement at " + str(index) }
            copied.push(statement)
            index = index + 1
        }
        index = 0
        while index < copied.length() {
            self._statements.push(copied.get(index))
            index = index + 1
        }
        return self
    }

    List<SqlStatement> statements() { return self._statements.copy() }
    Int size() { return self._statements.length() }
    Bool isEmpty() { return self._statements.length() == 0 }

    DbBatch clear() {
        self._statements.clear()
        return self
    }

    DbBatch copy() { return DbBatch.fromStatements(self._statements) }

    String describe() { return "DbBatch(statements=" + str(self._statements.length()) + ")" }
}

protocol RowMapper {
    Result<Unit, Error> start(Context context, List<SqlColumn> columns);
    Result<Unit, Error> mapRow(Context context, SqlRow row);
}


class PoolEntry {
    final SqlConnection connection
    final Long createdMono
    Long lastUsedMono
    Long leaseId

    PoolEntry(SqlConnection connection, Long createdMono, Long leaseId) {
        self.connection = connection
        self.createdMono = createdMono
        self.lastUsedMono = createdMono
        self.leaseId = leaseId
    }
}

class PooledConnection implements SqlConnection {
    final DatabasePool _pool
    final PoolEntry _entry
    final Long _leaseId
    Bool _open

    PooledConnection(DatabasePool pool, PoolEntry entry, Long leaseId) {
        self._pool = pool
        self._entry = entry
        self._leaseId = leaseId
        self._open = true
    }

    SqlDialect dialect() { return self._entry.connection.dialect() }
    Bool isOpen() { return self._open && self._entry.connection.isOpen() }

    Result<SqlResult, Error> execute(SqlStatement statement) {
        if !self.isOpen() { return Err(new BasicError(ErrorKind.Unavailable, "pooled connection is closed")) }
        return self._entry.connection.execute(statement)
    }

    Result<SqlResult, Error> executeWithOptions(SqlStatement statement, SqlOptions options) {
        if !self.isOpen() { return Err(new BasicError(ErrorKind.Unavailable, "pooled connection is closed")) }
        return self._entry.connection.executeWithOptions(statement, options)
    }

    Result<SqlTransaction, Error> begin() {
        if !self.isOpen() { return Err(new BasicError(ErrorKind.Unavailable, "pooled connection is closed")) }
        Result<SqlTransaction, Error> started = self._entry.connection.begin()
        if started.isErr() { return started }
        PooledTransaction transaction = new PooledTransaction(self, started.value())
        SqlTransaction result = transaction
        return Ok(result)
    }

    Result<Unit, Error> close() {
        if !self._open { return Ok() }
        self._open = false
        return self._pool.release(self._entry, self._leaseId)
    }
}

class PooledTransaction implements SqlTransaction {
    final PooledConnection _connection
    final SqlTransaction _transaction
    Bool _open

    PooledTransaction(PooledConnection connection, SqlTransaction transaction) {
        self._connection = connection
        self._transaction = transaction
        self._open = true
    }

    Result<SqlResult, Error> execute(SqlStatement statement) {
        if !self._open { return Err(new BasicError(ErrorKind.InvalidArgument, "transaction is closed")) }
        return self._transaction.execute(statement)
    }

    Result<SqlResult, Error> executeWithOptions(SqlStatement statement, SqlOptions options) {
        if !self._open { return Err(new BasicError(ErrorKind.InvalidArgument, "transaction is closed")) }
        return self._transaction.executeWithOptions(statement, options)
    }

    Result<Unit, Error> commit() {
        if !self._open { return Err(new BasicError(ErrorKind.InvalidArgument, "transaction is closed")) }
        self._open = false
        Result<Unit, Error> committed = self._transaction.commit()
        self._connection.close()
        return committed
    }

    Result<Unit, Error> rollback() {
        if !self._open { return Err(new BasicError(ErrorKind.InvalidArgument, "transaction is closed")) }
        self._open = false
        Result<Unit, Error> rolledBack = self._transaction.rollback()
        self._connection.close()
        return rolledBack
    }

    Bool isOpen() { return self._open && self._transaction.isOpen() }

    Result<Unit, Error> close() {
        if !self._open { return Ok() }
        self._open = false
        self._transaction.close()
        return self._connection.close()
    }
}

static Result<DatabasePool, Error> dbOpenPool(Context context, SqlDriver driver, DatabaseConfig config) {
    if context == null || driver == null || config == null { throw "DatabasePool.open: null argument" }
    DatabasePool pool = new DatabasePool(driver, config, driver.name())
    if config.failFast() {
        Map<String, String> options = config.openOptions()
        Result<SqlConnection, Error> opened = sqlDriverOpen(driver, config.connectionUri(), options)
        if opened.isErr() {
            pool.close()
            return Err(opened.error())
        }
        pool.adoptInitial(opened.value())
    }
    Result<DatabasePool, Error> result = Ok(pool)
    return result
}

class DatabasePool {
    final SqlDriver _driver
    final DatabaseConfig _config
    final RuntimeMonitor _monitor
    final String _driverName
    List<PoolEntry> _idle
    List<PoolEntry> _active
    Int _opening
    Int _waiting
    Long _nextLease
    Bool _closed
    Long _createdCount
    Long _closedCount
    Long _acquireCount
    Long _acquireTimeoutCount
    Long _validationFailureCount
    Long _leakedLeaseCount
    Long _waitCount
    Long _waitMillisTotal
    Long _maximumWaitMillis

    DatabasePool(SqlDriver driver, DatabaseConfig config, String driverName) {
        self._driver = driver
        self._config = config
        self._driverName = driverName
        self._monitor = new RuntimeMonitor()
        self._idle = []
        self._active = []
        self._opening = 0
        self._waiting = 0
        self._nextLease = 1
        self._closed = false
        self._createdCount = 0
        self._closedCount = 0
        self._acquireCount = 0
        self._acquireTimeoutCount = 0
        self._validationFailureCount = 0
        self._leakedLeaseCount = 0
        self._waitCount = 0
        self._waitMillisTotal = 0
        self._maximumWaitMillis = 0
    }

    static Result<DatabasePool, Error> open(Context context, SqlDriver driver, DatabaseConfig config) {
        return dbOpenPool(context, driver, config)
    }

    Void adoptInitial(SqlConnection connection) {
        Long timestamp = nowMono()
        PoolEntry entry = new PoolEntry(connection, timestamp, 0)
        self._idle.push(entry)
        self._createdCount = self._createdCount + 1
    }

    String name() { return self._config.name() }
    String driverName() { return self._driverName }
    Bool isOpen() { return !self._closed }
    DatabaseConfig config() { return self._config }

    Result<SqlConnection, Error> borrow(Context context) {
        if context == null { throw "DatabasePool.borrow: null context" }
        Context waitContext = context
        Context timerContext = null
        TaskGroup timerGroup = null
        Long acquireTimeout = self._config.acquireTimeoutMillis()
        if acquireTimeout > 0 {
            timerContext = Context.withCancel(context)
            timerGroup = TaskGroup.create(timerContext)
            Context captured = timerContext
            Long timeout = acquireTimeout
            timerGroup.spawn(() -> {
                Long start = nowMono()
                while !captured.isCancelled() && nowMono() - start < timeout {
                    sleepMs(2)
                }
                if !captured.isCancelled() { captured.cancel() }
                return Ok(1)
            })
            waitContext = timerContext
        }
        self._monitor.enter()
        Bool waited = false
        Long waitStart = 0
        while true {
            if self._closed {
                self._monitor.exit()
                if timerGroup != null { timerGroup.close() }
                return Err(new BasicError(ErrorKind.Unavailable, "database pool is closed"))
            }
            if self._idle.length() > 0 {
                PoolEntry entry = self._idle.get(self._idle.length() - 1)
                self._idle.remove(self._idle.length() - 1)
                Bool valid = true
                if self._config.validateOnAcquire() {
                    if !entry.connection.isOpen() {
                        valid = false
                    } else {
                        SqlStatement? validation = self._config.validationStatement()
                        if validation != null {
                            Result<SqlResult, Error> checked = entry.connection.execute(validation as SqlStatement)
                            if checked.isErr() { valid = false }
                        }
                    }
                }
                if !valid {
                    entry.connection.close()
                    self._closedCount = self._closedCount + 1
                    self._validationFailureCount = self._validationFailureCount + 1
                    continue
                }
                Long lease = self._nextLease
                self._nextLease = self._nextLease + 1
                entry.leaseId = lease
                entry.lastUsedMono = nowMono()
                self._active.push(entry)
                self._acquireCount = self._acquireCount + 1
                if waited {
                    Long elapsed = nowMono() - waitStart
                    self._waitMillisTotal = self._waitMillisTotal + elapsed
                    if elapsed > self._maximumWaitMillis { self._maximumWaitMillis = elapsed }
                }
                self._monitor.exit()
                if timerGroup != null { timerGroup.close() }
                PooledConnection pooled = new PooledConnection(self, entry, lease)
                SqlConnection result = pooled
                return Ok(result)
            }
            if self._active.length() + self._opening < self._config.maximumPoolSize() {
                self._opening = self._opening + 1
                self._monitor.exit()
                Map<String, String> options = self._config.openOptions()
                Result<SqlConnection, Error> opened = sqlDriverOpen(self._driver, self._config.connectionUri(), options)
                self._monitor.enter()
                self._opening = self._opening - 1
                if self._closed {
                    if opened.isOk() { opened.value().close() }
                    self._monitor.exit()
                    if timerGroup != null { timerGroup.close() }
                    return Err(new BasicError(ErrorKind.Unavailable, "database pool is closed"))
                }
                if opened.isErr() {
                    self._monitor.notifyAll()
                    self._monitor.exit()
                    if timerGroup != null { timerGroup.close() }
                    return Err(opened.error())
                }
                SqlConnection connection = opened.value()
                Long timestamp = nowMono()
                Long lease = self._nextLease
                self._nextLease = self._nextLease + 1
                PoolEntry entry = new PoolEntry(connection, timestamp, lease)
                self._active.push(entry)
                self._createdCount = self._createdCount + 1
                self._acquireCount = self._acquireCount + 1
                if waited {
                    Long elapsed = nowMono() - waitStart
                    self._waitMillisTotal = self._waitMillisTotal + elapsed
                    if elapsed > self._maximumWaitMillis { self._maximumWaitMillis = elapsed }
                }
                self._monitor.exit()
                if timerGroup != null { timerGroup.close() }
                PooledConnection pooled = new PooledConnection(self, entry, lease)
                SqlConnection result = pooled
                return Ok(result)
            }
            if !waited {
                waited = true
                waitStart = nowMono()
                self._waiting = self._waiting + 1
                self._waitCount = self._waitCount + 1
            }
            Bool signalled = self._monitor.waitContext(waitContext)
            if !signalled {
                self._waiting = self._waiting - 1
                Long elapsed = nowMono() - waitStart
                self._waitMillisTotal = self._waitMillisTotal + elapsed
                if elapsed > self._maximumWaitMillis { self._maximumWaitMillis = elapsed }
                Bool timedOut = timerContext != null && timerContext.isCancelled() && !context.isCancelled()
                if timedOut { self._acquireTimeoutCount = self._acquireTimeoutCount + 1 }
                self._monitor.exit()
                if timerGroup != null { timerGroup.close() }
                if timedOut {
                    return Err(new BasicError(ErrorKind.Timeout, "database pool acquire timeout"))
                }
                return Err(new BasicError(ErrorKind.Cancelled, "database pool acquire cancelled"))
            }
        }
    }

    Result<Unit, Error> release(PoolEntry entry, Long leaseId) {
        self._monitor.enter()
        Int index = -1
        Int scan = 0
        while scan < self._active.length() {
            if self._active.get(scan).leaseId == leaseId { index = scan; break }
            scan = scan + 1
        }
        if index < 0 {
            self._monitor.exit()
            return Ok()
        }
        self._active.remove(index)
        Long age = nowMono() - entry.createdMono
        Bool expired = self._config.maximumLifetimeMillis() > 0 && age >= self._config.maximumLifetimeMillis()
        if self._closed || expired || !entry.connection.isOpen() {
            entry.connection.close()
            self._closedCount = self._closedCount + 1
        } else {
            entry.lastUsedMono = nowMono()
            self._idle.push(entry)
        }
        self._monitor.notifyAll()
        self._monitor.exit()
        return Ok()
    }

    Result<Unit, Error> close() {
        self._monitor.enter()
        if self._closed {
            self._monitor.exit()
            return Ok()
        }
        self._closed = true
        List<PoolEntry> closing = []
        Int index = 0
        while index < self._idle.length() {
            closing.push(self._idle.get(index))
            index = index + 1
        }
        self._idle.clear()
        self._monitor.notifyAll()
        self._monitor.exit()
        index = 0
        while index < closing.length() {
            closing.get(index).connection.close()
            self._closedCount = self._closedCount + 1
            index = index + 1
        }
        return Ok()
    }

    DatabasePoolStats stats() {
        self._monitor.enter()
        Int total = self._idle.length() + self._active.length() + self._opening
        DatabasePoolStats snapshot = new DatabasePoolStats(self._config.name(),
            self._config.maximumPoolSize(), self._config.minimumIdle(),
            total, self._idle.length(), self._active.length(), self._opening,
            self._waiting, self._createdCount, self._closedCount,
            self._acquireCount, self._acquireTimeoutCount,
            self._validationFailureCount, self._leakedLeaseCount,
            self._waitCount, self._waitMillisTotal, self._maximumWaitMillis,
            nowMono(), self._closed)
        self._monitor.exit()
        return snapshot
    }
}

class Database {
    final DatabasePool _pool

    Database(DatabasePool pool) {
        if pool == null { throw "Database: null pool" }
        self._pool = pool
    }

    String name() { return self._pool.name() }
    String driverName() { return self._pool.driverName() }
    Bool isOpen() { return self._pool.isOpen() }
    DatabasePool pool() { return self._pool }
    DatabasePoolStats poolStats() { return self._pool.stats() }
    Result<SqlConnection, Error> borrow(Context context) { return self._pool.borrow(context) }

    Result<SqlResult, Error> execute(Context context, SqlStatement statement) {
        if statement == null { throw "Database.execute: null statement" }
        Result<SqlConnection, Error> acquired = self._pool.borrow(context)
        if acquired.isErr() { return Err(acquired.error()) }
        SqlConnection connection = acquired.value()
        Result<SqlResult, Error> result = connection.execute(statement)
        connection.close()
        return result
    }

    Result<SqlResult, Error> executeWithOptions(Context context, SqlStatement statement, SqlOptions options) {
        if statement == null || options == null { throw "Database.executeWithOptions: null argument" }
        Result<SqlConnection, Error> acquired = self._pool.borrow(context)
        if acquired.isErr() { return Err(acquired.error()) }
        SqlConnection connection = acquired.value()
        Result<SqlResult, Error> result = connection.executeWithOptions(statement, options)
        connection.close()
        return result
    }

    Result<SqlTransaction, Error> begin(Context context) {
        Result<SqlConnection, Error> acquired = self._pool.borrow(context)
        if acquired.isErr() { return Err(acquired.error()) }
        SqlConnection connection = acquired.value()
        Result<SqlTransaction, Error> started = connection.begin()
        if started.isErr() {
            connection.close()
            return Err(started.error())
        }
        return started
    }

    Result<Unit, Error> close() { return self._pool.close() }
}

class Db {
    private Db() { }

    static Result<DatabasePool, Error> openPool(Context context, SqlDriver driver, DatabaseConfig config) {
        return DatabasePool.open(context, driver, config)
    }

    static Result<Database, Error> open(Context context, SqlDriver driver, DatabaseConfig config) {
        Result<DatabasePool, Error> opened = DatabasePool.open(context, driver, config)
        if opened.isErr() { return Err(opened.error()) }
        Database database = new Database(opened.value())
        Result<Database, Error> result = Ok(database)
        return result
    }

    static String isolationOpenOptionKey() { return isolationOpenOptionKey() }
}

class DatabaseHealth implements HealthCheck {
    final Database _database
    final String _name
    HealthReport? _last

    DatabaseHealth(Database database) {
        if database == null { throw "DatabaseHealth: null database" }
        self._database = database
        self._name = "database." + database.name()
        self._last = null
    }

    String name() { return self._name }

    HealthReport check() {
        if self._last == null {
            return HealthReport.unhealthy("health not refreshed")
        }
        return self._last as HealthReport
    }

    HealthReport? lastReport() { return self._last }

    Result<HealthReport, Error> refresh(Context context) {
        if context == null { throw "DatabaseHealth.refresh: null context" }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "health refresh cancelled"))
        }
        if !self._database.isOpen() {
            HealthReport report = HealthReport.unhealthy("database pool is closed")
            self._last = report
            return Ok(report)
        }
        DatabasePoolStats stats = self._database.poolStats()
        Int expected = stats.idleConnections() + stats.activeConnections() + stats.openingConnections()
        if expected != stats.totalConnections() {
            HealthReport report = HealthReport.unhealthy("pool stats inconsistent")
            self._last = report
            return Ok(report)
        }
        Map<String, String> details = [:]
        details.put("total", str(stats.totalConnections()))
        details.put("max", str(stats.maximumConnections()))
        HealthReport report = HealthReport.of(HealthState.Healthy, "database healthy", details)
        self._last = report
        return Ok(report)
    }
}

// ---------- M6.6：迁移 ----------

RuntimeMonitor migrationProcessLock = new RuntimeMonitor()
Bool migrationProcessLockHeld = false

static Bool migrationDigit(String character) {
    return character.length() == 1 && "0123456789".indexOf(character) >= 0
}

static Bool migrationAlpha(String character) {
    if character.length() != 1 { return false }
    return "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".indexOf(character) >= 0
}

static List<String> migrationVersionSegments(String version) {
    if version == null || version == "" || version.length() > 64 {
        throw "Migration: invalid version"
    }
    List<String> segments = version.split(".")
    if segments.length() == 0 || segments.length() > 16 {
        throw "Migration: invalid version segment count"
    }
    Int index = 0
    while index < segments.length() {
        String segment = segments.get(index)
        if segment == "" || segment.length() > 18 {
            throw "Migration: invalid version segment"
        }
        if segment.length() > 1 && segment.substring(0, 1) == "0" {
            throw "Migration: version leading zero"
        }
        Int digitIndex = 0
        while digitIndex < segment.length() {
            if !migrationDigit(segment.substring(digitIndex, 1)) {
                throw "Migration: version is not decimal"
            }
            digitIndex = digitIndex + 1
        }
        index = index + 1
    }
    return segments
}

static Bool migrationVersionValid(String version) {
    if version == null || version == "" || version.length() > 64 { return false }
    List<String> segments = version.split(".")
    if segments.length() == 0 || segments.length() > 16 { return false }
    Int index = 0
    while index < segments.length() {
        String segment = segments.get(index)
        if segment == "" || segment.length() > 18 { return false }
        if segment.length() > 1 && segment.substring(0, 1) == "0" { return false }
        Int digitIndex = 0
        while digitIndex < segment.length() {
            if !migrationDigit(segment.substring(digitIndex, 1)) { return false }
            digitIndex = digitIndex + 1
        }
        index = index + 1
    }
    return true
}

static Int migrationCompareSegment(String left, String right) {
    if left.length() < right.length() { return -1 }
    if left.length() > right.length() { return 1 }
    Int index = 0
    while index < left.length() {
        Int leftDigit = "0123456789".indexOf(left.substring(index, 1))
        Int rightDigit = "0123456789".indexOf(right.substring(index, 1))
        if leftDigit < rightDigit { return -1 }
        if leftDigit > rightDigit { return 1 }
        index = index + 1
    }
    return 0
}

static Int migrationCompareVersions(String leftVersion, String rightVersion) {
    List<String> left = migrationVersionSegments(leftVersion)
    List<String> right = migrationVersionSegments(rightVersion)
    Int limit = left.length()
    if right.length() < limit { limit = right.length() }
    Int index = 0
    while index < limit {
        Int compared = migrationCompareSegment(left.get(index), right.get(index))
        if compared != 0 { return compared }
        index = index + 1
    }
    if left.length() < right.length() { return -1 }
    if left.length() > right.length() { return 1 }
    return 0
}

static Long migrationChecksum(String version, String name,
                              List<SqlStatement> up, List<SqlStatement> down) {
    String canonical = version + "\n" + name + "\n" + str(up.length()) + "\n"
    Int index = 0
    while index < up.length() {
        canonical = canonical + up.get(index).sql() + "\n"
        index = index + 1
    }
    canonical = canonical + str(down.length()) + "\n"
    index = 0
    while index < down.length() {
        canonical = canonical + down.get(index).sql() + "\n"
        index = index + 1
    }
    Bytes bytes = Bytes.fromString(canonical)
    Long hash = -3750763034362895579
    index = 0
    while index < bytes.length() {
        hash = hash ^ (bytes.get(index) as Long)
        hash = hash * 1099511628211
        index = index + 1
    }
    return hash
}

class Migration {
    final String _version
    final String _name
    final List<SqlStatement> _up
    final List<SqlStatement> _down
    final Long _checksum

    Migration(String version, String name, List<SqlStatement> up) {
        List<SqlStatement> noDown = []
        Migration built = new Migration(version, name, up, noDown)
        self._version = built._version
        self._name = built._name
        self._up = built._up
        self._down = built._down
        self._checksum = built._checksum
    }

    Migration(String version, String name, List<SqlStatement> up, List<SqlStatement> down) {
        if version == null || name == null || up == null { throw "Migration: null argument" }
        migrationVersionSegments(version)
        if name == "" || name.length() > 200 || name.trim() == "" {
            throw "Migration: invalid name"
        }
        if name.indexOf("\n") >= 0 || name.indexOf("\r") >= 0 || name.indexOf("\t") >= 0 {
            throw "Migration: name must be single-line"
        }
        if up.length() == 0 { throw "Migration: empty up statements" }
        List<SqlStatement> upCopy = []
        Int index = 0
        while index < up.length() {
            SqlStatement statement = up.get(index)
            if statement == null { throw "Migration: null up statement" }
            upCopy.push(statement)
            index = index + 1
        }
        List<SqlStatement> downCopy = []
        if down != null {
            index = 0
            while index < down.length() {
                SqlStatement statement = down.get(index)
                if statement == null { throw "Migration: null down statement" }
                downCopy.push(statement)
                index = index + 1
            }
        }
        self._version = version
        self._name = name
        self._up = upCopy
        self._down = downCopy
        self._checksum = migrationChecksum(version, name, upCopy, downCopy)
    }

    String version() { return self._version }
    String name() { return self._name }
    List<SqlStatement> upStatements() { return self._up.copy() }
    List<SqlStatement> downStatements() { return self._down.copy() }
    Int upStatementCount() { return self._up.length() }
    Int downStatementCount() { return self._down.length() }
    Bool hasRollback() { return self._down.length() > 0 }
    Long checksum() { return self._checksum }

    Int compareTo(Migration other) {
        if other == null { throw "Migration.compareTo: null" }
        return migrationCompareVersions(self._version, other.version())
    }

    static Int compareVersion(String leftVersion, String rightVersion) {
        if leftVersion == null || rightVersion == null { throw "Migration.compareVersion: null" }
        return migrationCompareVersions(leftVersion, rightVersion)
    }

    Bool equals(Migration other) {
        if other == null { return false }
        if self._version != other.version() || self._name != other.name() {
            return false
        }
        if self._checksum != other.checksum() { return false }
        if self._up.length() != other.upStatementCount() { return false }
        if self._down.length() != other.downStatementCount() { return false }
        Int index = 0
        List<SqlStatement> otherUp = other.upStatements()
        while index < self._up.length() {
            if !self._up.get(index).equals(otherUp.get(index)) { return false }
            index = index + 1
        }
        List<SqlStatement> otherDown = other.downStatements()
        index = 0
        while index < self._down.length() {
            if !self._down.get(index).equals(otherDown.get(index)) { return false }
            index = index + 1
        }
        return true
    }

    String describe() {
        return "Migration(version=" + self._version + " name=" + self._name +
            " up=" + str(self._up.length()) + " down=" + str(self._down.length()) +
            " checksum=" + str(self._checksum) + ")"
    }
}

static Bool migrationTableNameValid(String name) {
    if name == null || name == "" || name.length() > 56 { return false }
    String first = name.substring(0, 1)
    if !migrationAlpha(first) && first != "_" { return false }
    Int index = 1
    while index < name.length() {
        String character = name.substring(index, 1)
        if !migrationAlpha(character) && !migrationDigit(character) && character != "_" {
            return false
        }
        index = index + 1
    }
    return true
}

static Result<Unit, Error> migrationAcquireLock(Context context, Long timeoutMillis) {
    migrationProcessLock.enter()
    Long started = nowMono()
    while migrationProcessLockHeld {
        if context != null && context.isCancelled() {
            migrationProcessLock.exit()
            return Err(new BasicError(ErrorKind.Cancelled, "migration lock cancelled"))
        }
        if timeoutMillis > 0 && nowMono() - started >= timeoutMillis {
            migrationProcessLock.exit()
            return Err(new BasicError(ErrorKind.Timeout, "migration lock timeout"))
        }
        migrationProcessLock.exit()
        sleepMs(5)
        migrationProcessLock.enter()
    }
    migrationProcessLockHeld = true
    migrationProcessLock.exit()
    return Ok()
}

static Void migrationReleaseLock() {
    migrationProcessLock.enter()
    migrationProcessLockHeld = false
    migrationProcessLock.notifyAll()
    migrationProcessLock.exit()
}

static Long migrationParseLong(String text) {
    if text == null || text == "" { throw "MigrationRunner: invalid history number" }
    Int index = 0
    Bool negative = false
    if text.substring(0, 1) == "-" {
        negative = true
        index = 1
    }
    Long value = 0
    while index < text.length() {
        Int digit = "0123456789".indexOf(text.substring(index, 1))
        if digit < 0 { throw "MigrationRunner: invalid history number" }
        value = value * 10 + digit
        index = index + 1
    }
    if negative { value = -value }
    return value
}

static String migrationHistoryEncode(String version, String name, Long checksum, Long appliedAt) {
    return version + "\t" + name + "\t" + str(checksum) + "\t" + str(appliedAt)
}

static String migrationHistoryVersion(String entry) {
    return entry.split("\t").get(0)
}

static String migrationHistoryName(String entry) {
    return entry.split("\t").get(1)
}

static Long migrationHistoryChecksum(String entry) {
    return migrationParseLong(entry.split("\t").get(2))
}

static Long migrationHistoryAppliedAt(String entry) {
    return migrationParseLong(entry.split("\t").get(3))
}

class MigrationRunner {
    final Database _database
    final String _historyTable
    final Long _lockTimeoutMillis
    final Long _lockLeaseMillis

    MigrationRunner(Database database, String historyTable) {
        MigrationRunner built = new MigrationRunner(database, historyTable, 30000, 3600000)
        self._database = built._database
        self._historyTable = built._historyTable
        self._lockTimeoutMillis = built._lockTimeoutMillis
        self._lockLeaseMillis = built._lockLeaseMillis
    }

    MigrationRunner(Database database, String historyTable, Long lockTimeoutMillis) {
        MigrationRunner built = new MigrationRunner(database, historyTable, lockTimeoutMillis, 3600000)
        self._database = built._database
        self._historyTable = built._historyTable
        self._lockTimeoutMillis = built._lockTimeoutMillis
        self._lockLeaseMillis = built._lockLeaseMillis
    }

    MigrationRunner(Database database, String historyTable, Long lockTimeoutMillis, Long lockLeaseMillis) {
        if database == null || historyTable == null { throw "MigrationRunner: null argument" }
        if !migrationTableNameValid(historyTable) { throw "MigrationRunner: invalid history table" }
        if lockTimeoutMillis < 0 { throw "MigrationRunner: negative lock timeout" }
        if lockLeaseMillis < 1000 { throw "MigrationRunner: lock lease below 1000" }
        self._database = database
        self._historyTable = historyTable
        self._lockTimeoutMillis = lockTimeoutMillis
        self._lockLeaseMillis = lockLeaseMillis
    }

    String historyTable() { return self._historyTable }

    String describe() {
        return "MigrationRunner(history=" + self._historyTable +
            " lockTimeoutMs=" + str(self._lockTimeoutMillis) +
            " lockLeaseMs=" + str(self._lockLeaseMillis) + ")"
    }

    String _createHistorySql() {
        return "CREATE TABLE " + self._historyTable +
            " (version TEXT, name TEXT, checksum INTEGER, applied_at INTEGER, PRIMARY KEY (version))"
    }

    Result<Unit, Error> _ensureHistory(Context context) {
        Result<SqlResult, Error> created = self._database.execute(context, new SqlStatement(self._createHistorySql()))
        if created.isOk() { return Ok() }
        String message = created.error().describe().toLower()
        if message.indexOf("exist") >= 0 { return Ok() }
        return Err(created.error())
    }

    Result<List<String>, Error> _readHistory(Context context) {
        SqlStatement statement = new SqlStatement("SELECT version, name, checksum, applied_at FROM " + self._historyTable)
        Result<SqlResult, Error> result = self._database.execute(context, statement)
        if result.isErr() {
            ErrorKind kind = result.error().kind()
            if kind == ErrorKind.InvalidArgument || kind == ErrorKind.NotFound {
                List<String> emptyHistory = []
                return Ok(emptyHistory)
            }
            return Err(result.error())
        }
        List<SqlRow> rows = result.value().rows()
        List<String> history = []
        Int index = 0
        while index < rows.length() {
            SqlRow row = rows.get(index)
            if row.length() < 4 {
                return Err(new BasicError(ErrorKind.DataCorrupted, "migration history row is incomplete"))
            }
            history.push(migrationHistoryEncode(row.get(0).asString().value(),
                row.get(1).asString().value(), row.get(2).asLong().value(),
                row.get(3).asLong().value()))
            index = index + 1
        }
        return Ok(history)
    }

    Result<List<Migration>, Error> _prepare(List<Migration> migrations) {
        if migrations == null { throw "MigrationRunner: null migrations" }
        List<Migration> sorted = []
        Int index = 0
        while index < migrations.length() {
            Migration migration = migrations.get(index)
            if migration == null {
                return Err(new BasicError(ErrorKind.InvalidArgument, "migration list contains null"))
            }
            Int position = 0
            while position < sorted.length() && sorted.get(position).compareTo(migration) < 0 {
                position = position + 1
            }
            sorted.insert(position, migration)
            index = index + 1
        }
        index = 1
        while index < sorted.length() {
            if sorted.get(index - 1).compareTo(sorted.get(index)) == 0 {
                return Err(new BasicError(ErrorKind.InvalidArgument, "duplicate migration version"))
            }
            index = index + 1
        }
        return Ok(sorted)
    }

    Bool _isApplied(List<String> history, String version) {
        Int index = 0
        while index < history.length() {
            if migrationHistoryVersion(history.get(index)) == version { return true }
            index = index + 1
        }
        return false
    }

    Result<Unit, Error> _validateDrift(List<Migration> migrations, List<String> history) {
        Map<String, Migration> byVersion = [:]
        Int index = 0
        while index < migrations.length() {
            byVersion.put(migrations.get(index).version(), migrations.get(index))
            index = index + 1
        }
        index = 0
        while index < history.length() {
            String version = migrationHistoryVersion(history.get(index))
            if !byVersion.has(version) {
                return Err(new BasicError(ErrorKind.DataCorrupted, "unknown applied migration: " + version))
            }
            Migration migration = byVersion.getOr(version, migrations.get(0))
            if migrationHistoryName(history.get(index)) != migration.name() ||
               migrationHistoryChecksum(history.get(index)) != migration.checksum() {
                return Err(new BasicError(ErrorKind.DataCorrupted, "migration drift: " + version))
            }
            index = index + 1
        }
        return Ok()
    }

    Result<Unit, Error> _validateHistory(List<Migration> migrations, List<String> history, Bool checkOrder) {
        Result<Unit, Error> drift = self._validateDrift(migrations, history)
        if drift.isErr() { return drift }
        Int index = 0
        while index < history.length() {
            Int inner = index + 1
            while inner < history.length() {
                if migrationHistoryVersion(history.get(index)) == migrationHistoryVersion(history.get(inner)) {
                    return Err(new BasicError(ErrorKind.DataCorrupted, "duplicate history version"))
                }
                inner = inner + 1
            }
            index = index + 1
        }
        if !checkOrder { return Ok() }
        String maxApplied = ""
        index = 0
        while index < history.length() {
            String version = migrationHistoryVersion(history.get(index))
            if maxApplied == "" || migrationCompareVersions(version, maxApplied) > 0 {
                maxApplied = version
            }
            index = index + 1
        }
        if maxApplied != "" {
            index = 0
            while index < migrations.length() {
                Migration migration = migrations.get(index)
                if !self._isApplied(history, migration.version()) &&
                   migrationCompareVersions(migration.version(), maxApplied) < 0 {
                    return Err(new BasicError(ErrorKind.InvalidArgument, "out-of-order migration: " + migration.version()))
                }
                index = index + 1
            }
        }
        return Ok()
    }

    Result<Unit, Error> _applyUp(Context context, Migration migration, Long appliedAt) {
        Result<SqlConnection, Error> acquired = self._database.borrow(context)
        if acquired.isErr() { return Err(acquired.error()) }
        SqlConnection connection = acquired.value()
        Result<SqlTransaction, Error> started = connection.begin()
        if started.isErr() {
            connection.close()
            return Err(started.error())
        }
        SqlTransaction transaction = started.value()
        List<SqlStatement> statements = migration.upStatements()
        Int index = 0
        while index < statements.length() {
            Result<SqlResult, Error> executed = transaction.execute(statements.get(index))
            if executed.isErr() {
                transaction.rollback()
                connection.close()
                return Err(executed.error())
            }
            index = index + 1
        }
        SqlStatement insert = new SqlStatement("INSERT INTO " + self._historyTable + " VALUES (?, ?, ?, ?)")
        insert = insert.bind(SqlValue.ofString(migration.version()))
        insert = insert.bind(SqlValue.ofString(migration.name()))
        insert = insert.bind(SqlValue.ofLong(migration.checksum()))
        insert = insert.bind(SqlValue.ofLong(appliedAt))
        Result<SqlResult, Error> written = transaction.execute(insert)
        if written.isErr() {
            transaction.rollback()
            connection.close()
            return Err(written.error())
        }
        Result<Unit, Error> committed = transaction.commit()
        connection.close()
        if committed.isErr() { return Err(committed.error()) }
        return Ok()
    }

    Result<Unit, Error> _applyDown(Context context, Migration migration) {
        Result<SqlConnection, Error> acquired = self._database.borrow(context)
        if acquired.isErr() { return Err(acquired.error()) }
        SqlConnection connection = acquired.value()
        Result<SqlTransaction, Error> started = connection.begin()
        if started.isErr() {
            connection.close()
            return Err(started.error())
        }
        SqlTransaction transaction = started.value()
        List<SqlStatement> statements = migration.downStatements()
        Int index = 0
        while index < statements.length() {
            Result<SqlResult, Error> executed = transaction.execute(statements.get(index))
            if executed.isErr() {
                transaction.rollback()
                connection.close()
                return Err(executed.error())
            }
            index = index + 1
        }
        SqlStatement deleted = new SqlStatement("DELETE FROM " + self._historyTable + " WHERE version = ?")
        deleted = deleted.bind(SqlValue.ofString(migration.version()))
        Result<SqlResult, Error> removed = transaction.execute(deleted)
        if removed.isErr() {
            transaction.rollback()
            connection.close()
            return Err(removed.error())
        }
        Result<Unit, Error> committed = transaction.commit()
        connection.close()
        if committed.isErr() { return Err(committed.error()) }
        return Ok()
    }

    Result<Int, Error> _migrateToVersion(Context context, List<Migration> migrations,
                                         List<String> history, String targetVersion) {
        Long appliedAt = nowWall()
        Int applied = 0
        Int index = 0
        while index < migrations.length() {
            Migration migration = migrations.get(index)
            Bool withinTarget = true
            if targetVersion != "" && migrationCompareVersions(migration.version(), targetVersion) > 0 {
                withinTarget = false
            }
            if withinTarget && !self._isApplied(history, migration.version()) {
                Result<Unit, Error> result = self._applyUp(context, migration, appliedAt + applied)
                if result.isErr() { return Err(result.error()) }
                history.push(migrationHistoryEncode(migration.version(), migration.name(),
                    migration.checksum(), appliedAt + applied))
                applied = applied + 1
            }
            index = index + 1
        }
        return Ok(applied)
    }

    Result<Int, Error> migrate(Context context, List<Migration> migrations) {
        if context == null { throw "MigrationRunner.migrate: null context" }

        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "migration cancelled"))
        }
        Result<List<Migration>, Error> prepared = self._prepare(migrations)
        if prepared.isErr() { return Err(prepared.error()) }
        List<Migration> sorted = prepared.value()
        if sorted.length() == 0 { return Ok(0) }
        Result<Unit, Error> lock = migrationAcquireLock(context, self._lockTimeoutMillis)
        if lock.isErr() { return Err(lock.error()) }
        Result<Unit, Error> ensured = self._ensureHistory(context)
        if ensured.isErr() {
            migrationReleaseLock()
            return Err(ensured.error())
        }
        Result<List<String>, Error> historyResult = self._readHistory(context)
        if historyResult.isErr() {
            migrationReleaseLock()
            return Err(historyResult.error())
        }
        List<String> history = historyResult.value()
        Result<Unit, Error> valid = self._validateHistory(sorted, history, true)
        if valid.isErr() {
            migrationReleaseLock()
            return Err(valid.error())
        }
        Result<Int, Error> applied = self._migrateToVersion(context, sorted, history, "")
        migrationReleaseLock()
        return applied
    }

    Result<Int, Error> migrateTo(Context context, List<Migration> migrations, String targetVersion) {
        if context == null || targetVersion == null { throw "MigrationRunner.migrateTo: null argument" }

        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "migration cancelled"))
        }
        if !migrationVersionValid(targetVersion) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid target version"))
        }
        Result<List<Migration>, Error> prepared = self._prepare(migrations)
        if prepared.isErr() { return Err(prepared.error()) }
        List<Migration> sorted = prepared.value()
        Bool found = false
        Int index = 0
        while index < sorted.length() {
            if sorted.get(index).version() == targetVersion { found = true }
            index = index + 1
        }
        if !found {
            return Err(new BasicError(ErrorKind.InvalidArgument, "unknown target version"))
        }
        if sorted.length() == 0 { return Ok(0) }
        Result<Unit, Error> lock = migrationAcquireLock(context, self._lockTimeoutMillis)
        if lock.isErr() { return Err(lock.error()) }
        Result<Unit, Error> ensured = self._ensureHistory(context)
        if ensured.isErr() {
            migrationReleaseLock()
            return Err(ensured.error())
        }
        Result<List<String>, Error> historyResult = self._readHistory(context)
        if historyResult.isErr() {
            migrationReleaseLock()
            return Err(historyResult.error())
        }
        List<String> history = historyResult.value()
        Result<Unit, Error> valid = self._validateHistory(sorted, history, true)
        if valid.isErr() {
            migrationReleaseLock()
            return Err(valid.error())
        }
        Result<Int, Error> applied = self._migrateToVersion(context, sorted, history, targetVersion)
        migrationReleaseLock()
        return applied
    }

    Result<List<Migration>, Error> pending(Context context, List<Migration> migrations) {
        if context == null { throw "MigrationRunner.pending: null context" }

        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "migration cancelled"))
        }
        Result<List<Migration>, Error> prepared = self._prepare(migrations)
        if prepared.isErr() { return Err(prepared.error()) }
        Result<List<String>, Error> historyResult = self._readHistory(context)
        if historyResult.isErr() { return Err(historyResult.error()) }
        List<String> history = historyResult.value()
        Result<Unit, Error> valid = self._validateHistory(prepared.value(), history, false)
        if valid.isErr() { return Err(valid.error()) }
        List<Migration> result = []
        Int index = 0
        while index < prepared.value().length() {
            Migration migration = prepared.value().get(index)
            if !self._isApplied(history, migration.version()) { result.push(migration) }
            index = index + 1
        }
        return Ok(result)
    }

    Result<List<String>, Error> appliedVersions(Context context) {
        if context == null { throw "MigrationRunner.appliedVersions: null context" }

        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "migration cancelled"))
        }
        Result<List<String>, Error> historyResult = self._readHistory(context)
        if historyResult.isErr() { return Err(historyResult.error()) }
        List<String> versions = []
        Int index = 0
        while index < historyResult.value().length() {
            versions.push(migrationHistoryVersion(historyResult.value().get(index)))
            index = index + 1
        }
        return Ok(versions)
    }

    Result<Unit, Error> validate(Context context, List<Migration> migrations) {
        if context == null { throw "MigrationRunner.validate: null context" }

        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "migration cancelled"))
        }
        Result<List<Migration>, Error> prepared = self._prepare(migrations)
        if prepared.isErr() { return Err(prepared.error()) }
        Result<List<String>, Error> historyResult = self._readHistory(context)
        if historyResult.isErr() { return Err(historyResult.error()) }
        return self._validateHistory(prepared.value(), historyResult.value(), true)
    }

    Result<Int, Error> repair(Context context, List<Migration> migrations) {
        if context == null { throw "MigrationRunner.repair: null context" }

        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "migration cancelled"))
        }
        Result<List<Migration>, Error> prepared = self._prepare(migrations)
        if prepared.isErr() { return Err(prepared.error()) }
        Result<List<String>, Error> historyResult = self._readHistory(context)
        if historyResult.isErr() { return Err(historyResult.error()) }
        List<String> history = historyResult.value()
        Map<String, Migration> byVersion = [:]
        Int index = 0
        while index < prepared.value().length() {
            byVersion.put(prepared.value().get(index).version(), prepared.value().get(index))
            index = index + 1
        }
        Int updates = 0
        index = 0
        while index < history.length() {
            String version = migrationHistoryVersion(history.get(index))
            if !byVersion.has(version) {
                return Err(new BasicError(ErrorKind.DataCorrupted, "unknown applied migration: " + version))
            }
            Migration migration = byVersion.getOr(version, prepared.value().get(0))
            if migrationHistoryName(history.get(index)) != migration.name() ||
               migrationHistoryChecksum(history.get(index)) != migration.checksum() {
                updates = updates + 1
            }
            index = index + 1
        }
        if updates == 0 { return Ok(0) }
        Result<Unit, Error> lock = migrationAcquireLock(context, self._lockTimeoutMillis)
        if lock.isErr() { return Err(lock.error()) }
        Result<SqlConnection, Error> acquired = self._database.borrow(context)
        if acquired.isErr() {
            migrationReleaseLock()
            return Err(acquired.error())
        }
        SqlConnection connection = acquired.value()
        Result<SqlTransaction, Error> started = connection.begin()
        if started.isErr() {
            connection.close()
            migrationReleaseLock()
            return Err(started.error())
        }
        SqlTransaction transaction = started.value()
        Int updated = 0
        index = 0
        while index < history.length() {
            String version = migrationHistoryVersion(history.get(index))
            Migration migration = byVersion.getOr(version, prepared.value().get(0))
            if migrationHistoryName(history.get(index)) != migration.name() ||
               migrationHistoryChecksum(history.get(index)) != migration.checksum() {
                SqlStatement statement = new SqlStatement("UPDATE " + self._historyTable +
                    " SET name = ?, checksum = ? WHERE version = ?")
                statement = statement.bind(SqlValue.ofString(migration.name()))
                statement = statement.bind(SqlValue.ofLong(migration.checksum()))
                statement = statement.bind(SqlValue.ofString(version))
                Result<SqlResult, Error> executed = transaction.execute(statement)
                if executed.isErr() {
                    transaction.rollback()
                    connection.close()
                    migrationReleaseLock()
                    return Err(executed.error())
                }
                updated = updated + 1
            }
            index = index + 1
        }
        Result<Unit, Error> committed = transaction.commit()
        connection.close()
        migrationReleaseLock()
        if committed.isErr() { return Err(committed.error()) }
        return Ok(updated)
    }

    Result<Int, Error> _rollbackEntries(Context context, List<Migration> migrations,
                                        List<String> versionsToRollback) {
        Map<String, Migration> byVersion = [:]
        Int index = 0
        while index < migrations.length() {
            byVersion.put(migrations.get(index).version(), migrations.get(index))
            index = index + 1
        }
        index = 0
        while index < versionsToRollback.length() {
            String version = versionsToRollback.get(index)
            if !byVersion.has(version) {
                return Err(new BasicError(ErrorKind.DataCorrupted, "unknown applied migration: " + version))
            }
            Migration migration = byVersion.getOr(version, migrations.get(0))
            if !migration.hasRollback() {
                return Err(new BasicError(ErrorKind.Unsupported, "migration has no rollback: " + version))
            }
            index = index + 1
        }
        Int rolledBack = 0
        index = versionsToRollback.length() - 1
        while index >= 0 {
            Migration migration = byVersion.getOr(versionsToRollback.get(index), migrations.get(0))
            Result<Unit, Error> result = self._applyDown(context, migration)
            if result.isErr() { return Err(result.error()) }
            rolledBack = rolledBack + 1
            index = index - 1
        }
        return Ok(rolledBack)
    }

    Result<Int, Error> rollbackLast(Context context, List<Migration> migrations) {
        if context == null { throw "MigrationRunner.rollbackLast: null context" }

        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "migration cancelled"))
        }
        Result<List<Migration>, Error> prepared = self._prepare(migrations)
        if prepared.isErr() { return Err(prepared.error()) }
        Result<List<String>, Error> historyResult = self._readHistory(context)
        if historyResult.isErr() { return Err(historyResult.error()) }
        List<String> history = historyResult.value()
        if history.length() == 0 { return Ok(0) }
        List<String> targets = []
        targets.push(migrationHistoryVersion(history.get(history.length() - 1)))
        Result<Unit, Error> lock = migrationAcquireLock(context, self._lockTimeoutMillis)
        if lock.isErr() { return Err(lock.error()) }
        Result<Int, Error> result = self._rollbackEntries(context, prepared.value(), targets)
        migrationReleaseLock()
        return result
    }

    Result<Int, Error> rollbackTo(Context context, List<Migration> migrations, String targetVersion) {
        if context == null || targetVersion == null { throw "MigrationRunner.rollbackTo: null argument" }

        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "migration cancelled"))
        }
        if !migrationVersionValid(targetVersion) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid target version"))
        }
        Result<List<Migration>, Error> prepared = self._prepare(migrations)
        if prepared.isErr() { return Err(prepared.error()) }
        Result<List<String>, Error> historyResult = self._readHistory(context)
        if historyResult.isErr() { return Err(historyResult.error()) }
        List<String> history = historyResult.value()
        Int targetIndex = -1
        Int index = 0
        while index < history.length() {
            if migrationHistoryVersion(history.get(index)) == targetVersion { targetIndex = index }
            index = index + 1
        }
        if targetIndex < 0 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "target is not applied: " + targetVersion))
        }
        Bool inList = false
        index = 0
        while index < prepared.value().length() {
            if prepared.value().get(index).version() == targetVersion { inList = true }
            index = index + 1
        }
        if !inList {
            return Err(new BasicError(ErrorKind.InvalidArgument, "target is not in migrations: " + targetVersion))
        }
        List<String> targets = []
        index = targetIndex + 1
        while index < history.length() {
            targets.push(migrationHistoryVersion(history.get(index)))
            index = index + 1
        }
        if targets.length() == 0 { return Ok(0) }
        Result<Unit, Error> lock = migrationAcquireLock(context, self._lockTimeoutMillis)
        if lock.isErr() { return Err(lock.error()) }
        Result<Int, Error> result = self._rollbackEntries(context, prepared.value(), targets)
        migrationReleaseLock()
        return result
    }

    Result<Int, Error> rollbackAll(Context context, List<Migration> migrations) {
        if context == null { throw "MigrationRunner.rollbackAll: null context" }

        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "migration cancelled"))
        }
        Result<List<Migration>, Error> prepared = self._prepare(migrations)
        if prepared.isErr() { return Err(prepared.error()) }
        Result<List<String>, Error> historyResult = self._readHistory(context)
        if historyResult.isErr() { return Err(historyResult.error()) }
        List<String> history = historyResult.value()
        if history.length() == 0 { return Ok(0) }
        List<String> targets = []
        Int index = 0
        while index < history.length() {
            targets.push(migrationHistoryVersion(history.get(index)))
            index = index + 1
        }
        Result<Unit, Error> lock = migrationAcquireLock(context, self._lockTimeoutMillis)
        if lock.isErr() { return Err(lock.error()) }
        Result<Int, Error> result = self._rollbackEntries(context, prepared.value(), targets)
        migrationReleaseLock()
        return result
    }
}
