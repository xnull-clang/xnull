package xdk2.db
import xdk.db
import xdk.sql
import xdk.runtime
import xdk.errors
import xdk.tasks
import xdk.time
import MemoryFixture

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

class WaitFlag {
    Bool done
    WaitFlag() { self.done = false }
}

static DatabaseConfig poolConfig(Int maximum, Long timeout) {
    Map<String, String> options = [:]
    return new DatabaseConfig("pool", "memory://test/db", options, null, 0, maximum,
        timeout, 0, 0, 0, 0, true, true, null)
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

    MemoryDriver driver = new MemoryDriver()
    DatabaseConfig poolCfg = poolConfig(10, 1000)
    DatabasePool pool = DatabasePool.open(context, driver, poolCfg).value()
    print("open=" + str(pool.isOpen()) + "," + pool.name() + "," + pool.driverName())
    DatabasePoolStats opened = pool.stats()
    print("open-stats=" + str(opened.totalConnections()) + "," + str(opened.idleConnections()) + "," + str(opened.activeConnections()))

    SqlConnection lease = pool.borrow(context).value()
    print("borrow=" + str(lease.isOpen()) + "," + str(pool.stats().activeConnections()) + "," + str(pool.stats().idleConnections()))
    print("lease-close=" + str(lease.close().isOk()) + "," + str(lease.close().isOk()) + "," + str(lease.isOpen()))
    DatabasePoolStats returned = pool.stats()
    print("returned=" + str(returned.activeConnections()) + "," + str(returned.idleConnections()) + "," + str(returned.acquireCount()))

    Database database = new Database(pool)
    SqlStatement create = new SqlStatement("CREATE TABLE items (id INT, name TEXT)")
    print("create=" + str(database.execute(context, create).isOk()))
    SqlStatement insert = new SqlStatement("INSERT INTO items VALUES (?, ?)")
    insert = insert.bind(SqlValue.ofInt(1)).bind(SqlValue.ofString("one"))
    print("insert=" + str(database.execute(context, insert).isOk()))
    SqlStatement select = new SqlStatement("SELECT id, name FROM items")
    print("select=" + str(database.execute(context, select).value().rowCount()))

    SqlTransaction transaction = database.begin(context).value()
    SqlStatement txInsert = new SqlStatement("INSERT INTO items VALUES (?, ?)")
    txInsert = txInsert.bind(SqlValue.ofInt(2)).bind(SqlValue.ofString("two"))
    print("tx-exec=" + str(transaction.execute(txInsert).isOk()))
    print("tx-commit=" + str(transaction.commit().isOk()) + "," + str(transaction.isOpen()))
    print("tx-count=" + str(database.execute(context, select).value().rowCount()))

    SqlTransaction rollbackTx = database.begin(context).value()
    SqlStatement txInsert2 = new SqlStatement("INSERT INTO items VALUES (?, ?)")
    txInsert2 = txInsert2.bind(SqlValue.ofInt(3)).bind(SqlValue.ofString("three"))
    rollbackTx.execute(txInsert2)
    print("tx-rollback=" + str(rollbackTx.rollback().isOk()) + "," + str(database.execute(context, select).value().rowCount()))
    database.close()

    DatabasePool waitPool = DatabasePool.open(context, driver, poolConfig(1, 1000)).value()
    SqlConnection held = waitPool.borrow(context).value()
    Context groupContext = Context.background()
    TaskGroup group = TaskGroup.create(groupContext)
    WaitFlag flag = new WaitFlag()
    Task<Int> waiter = group.spawn(() -> {
        Result<SqlConnection, Error> acquired = waitPool.borrow(context)
        if acquired.isErr() { return Ok(0) }
        acquired.value().close()
        flag.done = true
        return Ok(1)
    })
    sleepMs(30)
    print("wait-before=" + str(flag.done))
    held.close()
    Result<Int, TaskError> joined = waiter.joinDeadline(nowMono() + 2000)
    print("wait-after=" + str(joined.isOk()) + "," + str(flag.done))
    group.close()
    waitPool.close()

    DatabasePool cancelPool = DatabasePool.open(context, driver, poolConfig(1, 1000)).value()
    SqlConnection cancelHeld = cancelPool.borrow(context).value()
    Context cancelled = Context.background()
    cancelled.cancel()
    Result<SqlConnection, Error> cancelledBorrow = cancelPool.borrow(cancelled)
    print("cancel=" + str(cancelledBorrow.isErr()) + "," + str(cancelledBorrow.error().kind() == ErrorKind.Cancelled))
    cancelHeld.close()
    cancelPool.close()

    DatabasePool timeoutPool = DatabasePool.open(context, driver, poolConfig(1, 40)).value()
    SqlConnection timeoutHeld = timeoutPool.borrow(context).value()
    Long started = nowMono()
    Result<SqlConnection, Error> timedOut = timeoutPool.borrow(context)
    Long elapsed = nowMono() - started
    print("timeout=" + str(timedOut.isErr()) + "," + str(timedOut.error().kind() == ErrorKind.Timeout) + "," + str(elapsed >= 20))
    print("timeout-count=" + str(timeoutPool.stats().acquireTimeoutCount()))
    timeoutPool.close()
    print("closed-borrow=" + str(timeoutPool.borrow(context).isErr()) + "," + str(timeoutHeld.close().isOk()) + "," + str(timeoutHeld.isOpen()))

    DatabasePool healthPool = DatabasePool.open(context, driver, poolConfig(2, 1000)).value()
    Database healthDb = new Database(healthPool)
    DatabaseHealth health = new DatabaseHealth(healthDb)
    print("health-name=" + health.name())
    print("health-initial=" + str(health.check().isHealthy()))
    Result<HealthReport, Error> refreshed = health.refresh(context)
    HealthReport healthyReport = refreshed.value()
    print("health-refresh=" + str(healthyReport.isHealthy()) + "," + str(health.check().isHealthy()))
    healthDb.close()
    Result<HealthReport, Error> closedReport = health.refresh(context)
    HealthReport unhealthyReport = closedReport.value()
    print("health-closed=" + str(unhealthyReport.isHealthy()) + "," + str(health.check().isHealthy()))
    return 0
}
