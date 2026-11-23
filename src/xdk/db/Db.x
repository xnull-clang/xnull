// xdk.db — database toolbox value types and protocols (M6.4a).
package xdk.db
import xdk.errors
import xdk.sql

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
