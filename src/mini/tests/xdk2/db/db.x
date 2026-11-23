package xdk2.db
import xdk.db
import xdk.sql
import xdk.runtime
import xdk.errors

class TestCheck implements HealthCheck {
    String name() { return "database" }
    HealthReport check() { return HealthReport.healthy("ok") }
}

class TestMapper implements RowMapper {
    Int started
    Int mapped
    TestMapper() { self.started = 0; self.mapped = 0 }
    Result<Unit, Error> start(Context context, List<SqlColumn> columns) {
        if context == null || columns == null { throw "TestMapper.start: null" }
        self.started = self.started + 1
        return Ok()
    }
    Result<Unit, Error> mapRow(Context context, SqlRow row) {
        if context == null || row == null { throw "TestMapper.mapRow: null" }
        self.mapped = self.mapped + 1
        return Ok()
    }
}

static Int main() {
    print("isolation=" + isolationLevelName(IsolationLevel.ReadUncommitted) + "," + isolationLevelName(IsolationLevel.ReadCommitted) + "," + isolationLevelName(IsolationLevel.RepeatableRead) + "," + isolationLevelName(IsolationLevel.Serializable))
    IsolationLevel? parsed = isolationLevelFromName(" READ COMMITTED ")
    IsolationLevel level = parsed as IsolationLevel
    print("isolation-parse=" + isolationLevelName(level) + "," + str(isolationLevelFromName("bogus") == null) + "," + isolationOpenOptionKey())

    DatabaseConfig config = DatabaseConfig.of("app", "postgres://user:secret@db/app")
    print("config=" + config.name() + "," + str(config.minimumIdle()) + "," + str(config.maximumPoolSize()) + "," + str(config.acquireTimeoutMillis()) + "," + str(config.idleTimeoutMillis()) + "," + str(config.maximumLifetimeMillis()) + "," + str(config.validationTimeoutMillis()) + "," + str(config.leakDetectionThresholdMillis()) + "," + str(config.failFast()) + "," + str(config.validateOnAcquire()) + "," + str(config.validationStatement() == null) + "," + str(config.openOptions().keys().length()) + "," + str(config.isolationLevel() == null))
    Map<String, String> options = [:]
    options.put("user", "secret-value")
    SqlStatement validation = new SqlStatement("select 1")
    DatabaseConfig full = new DatabaseConfig("app-1", "postgres://secret", options, IsolationLevel.Serializable, 2, 20, 4000, 5000, 6000, 1000, 2000, false, false, validation)
    print("config-custom=" + full.name() + "," + str(full.minimumIdle()) + "," + str(full.maximumPoolSize()) + "," + str(full.acquireTimeoutMillis()) + "," + str(full.idleTimeoutMillis()) + "," + str(full.maximumLifetimeMillis()) + "," + str(full.validationTimeoutMillis()) + "," + str(full.leakDetectionThresholdMillis()) + "," + str(full.failFast()) + "," + str(full.validateOnAcquire()) + "," + str(full.validationStatement() != null) + "," + isolationLevelName(full.isolationLevel() as IsolationLevel) + "," + str(full.openOptions().keys().length()))
    Map<String, String> mutated = full.openOptions()
    mutated.put("extra", "x")
    print("config-copy-map=" + str(full.openOptions().keys().length()))
    DatabaseConfig derived = full.withOpenOption("region", "eu").withPoolSize(3, 30).withIsolationLevel(IsolationLevel.RepeatableRead).withFailFast(true)
    print("config-derived=" + str(derived.minimumIdle()) + "," + str(derived.maximumPoolSize()) + "," + isolationLevelName(derived.isolationLevel() as IsolationLevel) + "," + str(derived.failFast()) + "," + str(derived.openOptions().keys().length()))
    String described = full.describe()
    print("config-describe=" + str(described.indexOf("secret") < 0) + "," + str(described.indexOf("postgres://") < 0) + "," + str(described.indexOf("options=1") >= 0))
    DatabaseConfig copiedConfig = full.copy()
    print("config-copy=" + str(copiedConfig.name() == full.name()) + "," + str(copiedConfig.openOptions().keys().length() == full.openOptions().keys().length()))

    DatabasePoolStats stats = new DatabasePoolStats("app", 10, 2, 7, 3, 3, 1, 2, 20, 13, 100, 4, 1, 2, 50, 5000, 300, 0, false)
    print("stats=" + stats.name() + "," + str(stats.totalConnections()) + "," + str(stats.idleConnections()) + "," + str(stats.activeConnections()) + "," + str(stats.openingConnections()) + "," + str(stats.waitingRequests()) + "," + stats.describe())
    print("stats-derived=" + str(stats.utilization()) + "," + str(stats.averageWaitMillis()) + "," + str(stats.isSaturated()) + "," + str(stats.isIdle()))
    DatabasePoolStats statsCopy = stats.copy()
    print("stats-copy=" + str(statsCopy.equals(stats)) + "," + statsCopy.describe())
    DatabasePoolStats idle = new DatabasePoolStats("app", 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false)
    print("stats-idle=" + str(idle.isIdle()) + "," + str(idle.utilization()) + "," + str(idle.averageWaitMillis()))

    DbBatch batch = new DbBatch()
    batch = batch.add(new SqlStatement("insert 1"))
    List<SqlStatement> more = []
    more.push(new SqlStatement("insert 2"))
    more.push(new SqlStatement("insert 3"))
    batch = batch.addAll(more)
    print("batch=" + str(batch.size()) + "," + str(batch.isEmpty()) + "," + batch.describe())
    List<SqlStatement> snapshot = batch.statements()
    snapshot.clear()
    print("batch-snapshot=" + str(batch.size()))
    DbBatch batchCopy = batch.copy()
    batch.clear()
    print("batch-copy=" + str(batchCopy.size()) + "," + str(batch.isEmpty()))

    TestCheck check = new TestCheck()
    print("health-check=" + check.name() + "," + str(check.check().isHealthy()))
    Context context = Context.background()
    List<SqlColumn> columns = []
    columns.push(new SqlColumn("id", "INT", false))
    List<SqlValue> values = []
    values.push(SqlValue.ofInt(1))
    TestMapper mapper = new TestMapper()
    print("mapper-start=" + str(mapper.start(context, columns).isOk()))
    print("mapper-row=" + str(mapper.mapRow(context, new SqlRow(values)).isOk()) + "," + str(mapper.started) + "," + str(mapper.mapped))
    return 0
}
