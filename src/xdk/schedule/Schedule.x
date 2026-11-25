// xdk.schedule —— 一次性/固定频率/固定延迟/cron 调度（M21.2）
//
// 单循环调度；不做持久化、分布式、多 worker 并行。
// Cron 支持 5 字段、* n a-b a,b */n a-b/n；DOM/DOW 同时受限时按 AND。
// 稳定性：preview。合同见 docs/design/utils/schedule/。
package xdk.schedule
import xdk.errors
import xdk.runtime
import xdk.time
import xdk.text

// ---------- 枚举 ----------
enum ScheduleKind {
    Once,
    FixedRate,
    FixedDelay,
    Cron,
}

String scheduleKindName(ScheduleKind kind) {
    if kind == ScheduleKind.Once { return "once" }
    if kind == ScheduleKind.FixedRate { return "fixed_rate" }
    if kind == ScheduleKind.FixedDelay { return "fixed_delay" }
    return "cron"
}

enum MisfirePolicy {
    Skip,
    FireOnce,
    CatchUp,
}

String misfirePolicyName(MisfirePolicy policy) {
    if policy == MisfirePolicy.Skip { return "skip" }
    if policy == MisfirePolicy.FireOnce { return "fire_once" }
    return "catch_up"
}

// ---------- CronExpression ----------
class CronExpression {
    final String _text
    final List<Int> _minutes
    final List<Int> _hours
    final List<Int> _days
    final List<Int> _months
    final List<Int> _weekdays
    final Bool _domWildcard
    final Bool _dowWildcard

    private CronExpression(String text, List<Int> minutes, List<Int> hours,
                           List<Int> days, List<Int> months, List<Int> weekdays,
                           Bool domWildcard, Bool dowWildcard) {
        self._text = text
        self._minutes = minutes
        self._hours = hours
        self._days = days
        self._months = months
        self._weekdays = weekdays
        self._domWildcard = domWildcard
        self._dowWildcard = dowWildcard
    }

    static Result<CronExpression, Error> parse(String text) {
        if text == null { throw "CronExpression.parse: null text" }
        List<String> parts = []
        List<String> raw = text.trim().split(" ")
        Int index = 0
        while index < raw.length() {
            String part = raw.get(index).trim()
            if part != "" { parts.push(part) }
            index = index + 1
        }
        if parts.length() != 5 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "cron: expected 5 fields"))
        }
        Result<List<Int>, Error> minutes = cronParseField(parts.get(0), 0, 59, "minute")
        if minutes.isErr() { return Err(minutes.error()) }
        Result<List<Int>, Error> hours = cronParseField(parts.get(1), 0, 23, "hour")
        if hours.isErr() { return Err(hours.error()) }
        Result<List<Int>, Error> days = cronParseField(parts.get(2), 1, 31, "day")
        if days.isErr() { return Err(days.error()) }
        Result<List<Int>, Error> months = cronParseField(parts.get(3), 1, 12, "month")
        if months.isErr() { return Err(months.error()) }
        Result<List<Int>, Error> weekdays = cronParseField(parts.get(4), 0, 6, "weekday")
        if weekdays.isErr() { return Err(weekdays.error()) }
        List<Int> minuteValues = minutes.value()
        List<Int> dayValues = days.value()
        List<Int> weekdayValues = weekdays.value()
        Bool domWildcard = cronIsFull(dayValues, 1, 31)
        Bool dowWildcard = cronIsFull(weekdayValues, 0, 6)
        return Ok(new CronExpression(text, minuteValues, hours.value(), dayValues,
            months.value(), weekdayValues, domWildcard, dowWildcard))
    }

    Result<Long, Error> next(Long fromEpochMillis, TimeZone zone) {
        if zone == null { throw "CronExpression.next: null zone" }
        Long offset = zone.offsetMillis() as Long
        Long minute = fromEpochMillis / (60000 as Long)
        if fromEpochMillis < 0 as Long && fromEpochMillis % (60000 as Long) != 0 as Long {
            minute = minute - 1 as Long
        }
        Long candidate = (minute + 1 as Long) * (60000 as Long)
        DateTime local = new DateTime(candidate + offset)
        Int limitYear = local.year() + 5
        while local.year() <= limitYear {
            if self.matchesLocal(local) { return Ok(candidate) }
            candidate = candidate + (60000 as Long)
            local = new DateTime(candidate + offset)
        }
        return Err(new BasicError(ErrorKind.InvalidArgument, "cron: no future time"))
    }

    Result<List<Long>, Error> nextN(Long fromEpochMillis, TimeZone zone, Int count) {
        if zone == null { throw "CronExpression.nextN: null zone" }
        if count < 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "cron: count must be positive"))
        }
        List<Long> result = []
        Long cursor = fromEpochMillis
        Int index = 0
        while index < count {
            Result<Long, Error> value = self.next(cursor, zone)
            if value.isErr() { break }
            result.push(value.value())
            cursor = value.value()
            index = index + 1
        }
        return Ok(result)
    }

    Bool matches(Long epochMillis, TimeZone zone) {
        if zone == null { throw "CronExpression.matches: null zone" }
        DateTime local = new DateTime(epochMillis + (zone.offsetMillis() as Long))
        return self.matchesLocal(local)
    }

    String text() { return self._text }

    String describe() { return "cron(" + self._text + ")" }

    private Bool matchesLocal(DateTime local) {
        if !cronContains(self._minutes, local.minute()) { return false }
        if !cronContains(self._hours, local.hour()) { return false }
        if !cronContains(self._months, local.month()) { return false }
        Bool dom = cronContains(self._days, local.day())
        Bool dow = cronContains(self._weekdays, local.weekday())
        if self._domWildcard && self._dowWildcard { return true }
        if self._domWildcard { return dow }
        if self._dowWildcard { return dom }
        return dom && dow
    }
}

// ---------- Schedule ----------
class Schedule {
    final ScheduleKind _kind
    final Long _delayMillis
    final Long _initialDelayMillis
    final Long _periodMillis
    final CronExpression? _cron
    final Long _atEpochMillis
    final Bool _absolute

    private Schedule(ScheduleKind kind, Long delayMillis, Long initialDelayMillis,
                     Long periodMillis, CronExpression? cron, Long atEpochMillis,
                     Bool absolute) {
        self._kind = kind
        self._delayMillis = delayMillis
        self._initialDelayMillis = initialDelayMillis
        self._periodMillis = periodMillis
        self._cron = cron
        self._atEpochMillis = atEpochMillis
        self._absolute = absolute
    }

    static Schedule once(Long delayMillis) {
        if delayMillis < 0 as Long { throw "Schedule.once: negative delay" }
        return new Schedule(ScheduleKind.Once, delayMillis, 0 as Long, 0 as Long,
            null, 0 as Long, false)
    }

    static Schedule at(Long epochMillis) {
        return new Schedule(ScheduleKind.Once, 0 as Long, 0 as Long, 0 as Long,
            null, epochMillis, true)
    }

    static Schedule fixedRate(Long periodMillis) {
        return Schedule.fixedRateWithDelay(0 as Long, periodMillis)
    }

    static Schedule fixedRateWithDelay(Long initialDelayMillis, Long periodMillis) {
        if initialDelayMillis < 0 as Long || periodMillis <= 0 as Long {
            throw "Schedule.fixedRate: invalid period"
        }
        return new Schedule(ScheduleKind.FixedRate, 0 as Long, initialDelayMillis,
            periodMillis, null, 0 as Long, false)
    }

    static Schedule fixedDelay(Long delayMillis) {
        return Schedule.fixedDelayWithDelay(0 as Long, delayMillis)
    }

    static Schedule fixedDelayWithDelay(Long initialDelayMillis, Long delayMillis) {
        if initialDelayMillis < 0 as Long || delayMillis <= 0 as Long {
            throw "Schedule.fixedDelay: invalid delay"
        }
        return new Schedule(ScheduleKind.FixedDelay, delayMillis, initialDelayMillis,
            delayMillis, null, 0 as Long, false)
    }

    static Schedule cron(String text) {
        Result<CronExpression, Error> parsed = CronExpression.parse(text)
        if parsed.isErr() { throw "Schedule.cron: invalid expression" }
        return Schedule.cronExpressionOf(parsed.value())
    }

    static Schedule cronExpressionOf(CronExpression expression) {
        if expression == null { throw "Schedule.cronExpressionOf: null" }
        return new Schedule(ScheduleKind.Cron, 0 as Long, 0 as Long, 0 as Long,
            expression, 0 as Long, false)
    }

    ScheduleKind kind() { return self._kind }
    Long delayMillis() { return self._delayMillis }
    Long initialDelayMillis() { return self._initialDelayMillis }
    Long periodMillis() { return self._periodMillis }
    CronExpression? cronExpression() { return self._cron }
    Long atEpochMillis() { return self._atEpochMillis }
    Bool isAbsolute() { return self._absolute }

    String describe() {
        if self._kind == ScheduleKind.Once {
            if self._absolute { return "once at " + str(self._atEpochMillis) }
            return "once after " + str(self._delayMillis)
        }
        if self._kind == ScheduleKind.FixedRate {
            return "fixedRate initial=" + str(self._initialDelayMillis) +
                " period=" + str(self._periodMillis)
        }
        if self._kind == ScheduleKind.FixedDelay {
            return "fixedDelay initial=" + str(self._initialDelayMillis) +
                " delay=" + str(self._periodMillis)
        }
        if self._cron == null { return "cron" }
        CronExpression expression = self._cron as CronExpression
        return expression.describe()
    }
}

// ---------- Job / JobHandle ----------
protocol Job {
    Result<Unit, Error> run(Context context);
}

class JobHandle {
    final Long _id
    final String _name
    final Schedule _schedule
    Bool _cancelled

    JobHandle(Long id, String name, Schedule schedule, Bool cancelled) {
        if id < 0 as Long || name == null || name == "" || schedule == null {
            throw "JobHandle: invalid field"
        }
        self._id = id
        self._name = name
        self._schedule = schedule
        self._cancelled = cancelled
    }

    Long id() { return self._id }
    String name() { return self._name }
    Schedule schedule() { return self._schedule }
    Bool isCancelled() { return self._cancelled }

    Void markCancelled() { self._cancelled = true }

    String describe() {
        return "job " + str(self._id) + " " + self._name + " " +
            scheduleKindName(self._schedule.kind()) +
            " cancelled=" + str(self._cancelled)
    }
}

// ---------- SchedulerOptions ----------
class SchedulerOptions {
    Int _workerCount
    Int _maxPending
    MisfirePolicy _misfirePolicy
    TimeZone _defaultTimeZone
    Long _shutdownTimeoutMillis
    Int _catchUpLimit

    SchedulerOptions() {
        self._workerCount = 1
        self._maxPending = 1024
        self._misfirePolicy = MisfirePolicy.Skip
        self._defaultTimeZone = TimeZone.utc()
        self._shutdownTimeoutMillis = 30000 as Long
        self._catchUpLimit = 10
    }

    SchedulerOptions workerCount(Int value) {
        if value < 1 { throw "SchedulerOptions.workerCount: < 1" }
        self._workerCount = value
        return self
    }

    SchedulerOptions maxPending(Int value) {
        if value < 1 { throw "SchedulerOptions.maxPending: < 1" }
        self._maxPending = value
        return self
    }

    SchedulerOptions misfirePolicy(MisfirePolicy value) {
        self._misfirePolicy = value
        return self
    }

    SchedulerOptions defaultTimeZone(TimeZone value) {
        if value == null { throw "SchedulerOptions.defaultTimeZone: null" }
        self._defaultTimeZone = value
        return self
    }

    SchedulerOptions shutdownTimeoutMillis(Long value) {
        if value < 0 as Long {
            throw "SchedulerOptions.shutdownTimeoutMillis: negative"
        }
        self._shutdownTimeoutMillis = value
        return self
    }

    SchedulerOptions catchUpLimit(Int value) {
        if value < 0 { throw "SchedulerOptions.catchUpLimit: negative" }
        self._catchUpLimit = value
        return self
    }

    Int getWorkerCount() { return self._workerCount }
    Int getMaxPending() { return self._maxPending }
    MisfirePolicy getMisfirePolicy() { return self._misfirePolicy }
    TimeZone getDefaultTimeZone() { return self._defaultTimeZone }
    Long getShutdownTimeoutMillis() { return self._shutdownTimeoutMillis }
    Int getCatchUpLimit() { return self._catchUpLimit }

    SchedulerOptions copy() {
        SchedulerOptions result = new SchedulerOptions()
        result._workerCount = self._workerCount
        result._maxPending = self._maxPending
        result._misfirePolicy = self._misfirePolicy
        result._defaultTimeZone = self._defaultTimeZone
        result._shutdownTimeoutMillis = self._shutdownTimeoutMillis
        result._catchUpLimit = self._catchUpLimit
        return result
    }
}

// ---------- Scheduler ----------
class Scheduler {
    final SchedulerOptions _options
    final RuntimeMonitor _monitor
    final List<Job> _jobs
    final List<JobHandle> _handles
    final List<Long> _nextAt
    TaskGroup? _group
    Bool _shutdown
    Long _nextId

    private Scheduler(SchedulerOptions options) {
        self._options = options.copy()
        self._monitor = new RuntimeMonitor()
        self._jobs = []
        self._handles = []
        self._nextAt = []
        self._group = null
        self._shutdown = false
        self._nextId = 1 as Long
    }

    static Scheduler create(SchedulerOptions options) {
        if options == null { throw "Scheduler.create: null options" }
        Scheduler scheduler = new Scheduler(options)
        TaskGroup group = TaskGroup.create(Context.withCancel(Context.background()))
        scheduler._group = group
        Task<Int> task = group.spawn((Context taskContext) -> {
            scheduler.runLoop(taskContext)
            return Ok(0)
        })
        return scheduler
    }

    Result<JobHandle, Error> schedule(Job job, Schedule schedule) {
        if job == null || schedule == null {
            throw "Scheduler.schedule: null argument"
        }
        self._monitor.enter()
        if self._shutdown {
            self._monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "scheduler is shut down"))
        }
        Int active = self.activeCount()
        if active >= self._options.getMaxPending() {
            self._monitor.exit()
            return Err(new BasicError(ErrorKind.Busy, "scheduler maxPending reached"))
        }
        JobHandle handle = new JobHandle(self._nextId, "job-" + str(self._nextId),
            schedule, false)
        self._nextId = self._nextId + 1 as Long
        self._jobs.push(job)
        self._handles.push(handle)
        self._nextAt.push(self.initialNext(schedule))
        self._monitor.notifyAll()
        self._monitor.exit()
        return Ok(handle)
    }

    Bool cancel(JobHandle handle) {
        if handle == null { throw "Scheduler.cancel: null handle" }
        self._monitor.enter()
        Int index = self.indexOf(handle)
        if index < 0 {
            self._monitor.exit()
            return false
        }
        JobHandle found = self._handles.get(index)
        if found.isCancelled() {
            self._monitor.exit()
            return false
        }
        found.markCancelled()
        self._monitor.notifyAll()
        self._monitor.exit()
        return true
    }

    Result<Unit, Error> trigger(JobHandle handle) {
        if handle == null { throw "Scheduler.trigger: null handle" }
        self._monitor.enter()
        if self._shutdown {
            self._monitor.exit()
            return Err(new BasicError(ErrorKind.Unavailable, "scheduler is shut down"))
        }
        Int index = self.indexOf(handle)
        if index < 0 || self._handles.get(index).isCancelled() {
            self._monitor.exit()
            return Err(new BasicError(ErrorKind.NotFound, "job not found"))
        }
        Job job = self._jobs.get(index)
        self._monitor.exit()
        return job.run(Context.background())
    }

    List<JobHandle> jobs() {
        self._monitor.enter()
        List<JobHandle> result = self._handles.copy()
        self._monitor.exit()
        return result
    }

    Result<Unit, Error> shutdown(Context context) {
        if context == null { throw "Scheduler.shutdown: null context" }
        self._monitor.enter()
        if self._shutdown {
            self._monitor.exit()
            return Ok()
        }
        self._shutdown = true
        self._monitor.notifyAll()
        self._monitor.exit()
        if self._group != null {
            TaskGroup group = self._group as TaskGroup
            group.close()
        }
        return Ok()
    }

    Bool isShutdown() {
        self._monitor.enter()
        Bool result = self._shutdown
        self._monitor.exit()
        return result
    }

    SchedulerOptions options() { return self._options.copy() }

    private Int activeCount() {
        Int count = 0
        Int index = 0
        while index < self._handles.length() {
            if !self._handles.get(index).isCancelled() { count = count + 1 }
            index = index + 1
        }
        return count
    }

    private Int indexOf(JobHandle handle) {
        Int index = 0
        while index < self._handles.length() {
            if self._handles.get(index) == handle { return index }
            index = index + 1
        }
        return -1
    }

    private Long initialNext(Schedule schedule) {
        Long mono = nowMono()
        if schedule.kind() == ScheduleKind.Once {
            if schedule.isAbsolute() {
                Long delay = schedule.atEpochMillis() - nowWallMs()
                if delay < 0 as Long { delay = 0 as Long }
                return mono + delay
            }
            return mono + schedule.delayMillis()
        }
        if schedule.kind() == ScheduleKind.FixedRate ||
            schedule.kind() == ScheduleKind.FixedDelay {
            return mono + schedule.initialDelayMillis()
        }
        CronExpression? maybe = schedule.cronExpression()
        if maybe == null { return mono + (60000 as Long) }
        CronExpression expression = maybe as CronExpression
        Result<Long, Error> next = expression.next(nowWallMs(),
            self._options.getDefaultTimeZone())
        if next.isErr() { return mono + (31536000000 as Long) }
        Long delay = next.value() - nowWallMs()
        if delay < 0 as Long { delay = 0 as Long }
        return mono + delay
    }

    private Void runLoop(Context context) {
        while !context.isCancelled() {
            self._monitor.enter()
            if self._shutdown {
                self._monitor.exit()
                return
            }
            Int active = self.activeCount()
            if active == 0 {
                Bool woke = self._monitor.waitContext(context)
                self._monitor.exit()
                if !woke { return }
                continue
            }
            Long now = nowMono()
            Int dueIndex = -1
            Long earliest = 0 as Long
            Bool earliestSet = false
            Int index = 0
            while index < self._handles.length() {
                JobHandle handle = self._handles.get(index)
                if !handle.isCancelled() {
                    Long next = self._nextAt.get(index)
                    if next <= now && dueIndex < 0 { dueIndex = index }
                    if !earliestSet || next < earliest {
                        earliest = next
                        earliestSet = true
                    }
                }
                index = index + 1
            }
            if dueIndex >= 0 {
                Job job = self._jobs.get(dueIndex)
                JobHandle handle = self._handles.get(dueIndex)
                Schedule schedule = handle.schedule()
                self.advance(dueIndex, schedule, now)
                self._monitor.exit()
                job.run(context)
                continue
            }
            if !earliestSet {
                self._monitor.exit()
                continue
            }
            Int state = self._monitor.waitDeadline(context, earliest)
            self._monitor.exit()
            if state == 0 { return }
        }
    }

    private Void advance(Int index, Schedule schedule, Long now) {
        if schedule.kind() == ScheduleKind.Once {
            self._handles.get(index).markCancelled()
            return
        }
        if schedule.kind() == ScheduleKind.FixedRate {
            Long next = self._nextAt.get(index) + schedule.periodMillis()
            if self._options.getMisfirePolicy() == MisfirePolicy.Skip && next <= now {
                next = now + schedule.periodMillis()
            }
            self._nextAt.set(index, next)
            return
        }
        if schedule.kind() == ScheduleKind.FixedDelay {
            self._nextAt.set(index, now + schedule.delayMillis())
            return
        }
        CronExpression? maybe = schedule.cronExpression()
        if maybe == null {
            self._handles.get(index).markCancelled()
            return
        }
        CronExpression expression = maybe as CronExpression
        Result<Long, Error> next = expression.next(nowWallMs(),
            self._options.getDefaultTimeZone())
        if next.isErr() {
            self._handles.get(index).markCancelled()
            return
        }
        Long delay = next.value() - nowWallMs()
        if delay < 0 as Long { delay = 0 as Long }
        self._nextAt.set(index, nowMono() + delay)
    }
}

// ---------- 内部 cron 解析辅助 ----------
static Bool cronContains(List<Int> values, Int value) {
    Int index = 0
    while index < values.length() {
        if values.get(index) == value { return true }
        index = index + 1
    }
    return false
}

static Void cronAddUnique(List<Int> values, Int value) {
    if !cronContains(values, value) { values.push(value) }
}

static Bool cronIsFull(List<Int> values, Int min, Int max) {
    Int count = max - min + 1
    return values.length() == count
}

static Result<List<Int>, Error> cronParseField(String text, Int min, Int max, String name) {
    if text == null || text == "" {
        return Err(new BasicError(ErrorKind.InvalidArgument, "cron: empty " + name))
    }
    if text == "*" || text == "?" {
        List<Int> all = []
        Int value = min
        while value <= max {
            all.push(value)
            value = value + 1
        }
        return Ok(all)
    }
    List<Int> result = []
    List<String> parts = text.split(",")
    Int partIndex = 0
    while partIndex < parts.length() {
        String part = parts.get(partIndex).trim()
        if part == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "cron: empty " + name + " item"))
        }
        Int slash = part.indexOf("/")
        String base = part
        Int step = 1
        if slash >= 0 {
            base = part.substring(0, slash)
            Result<Int, Error> parsedStep = parseInt(part.substring(slash + 1,
                part.length() - slash - 1))
            if parsedStep.isErr() || parsedStep.value() < 1 {
                return Err(new BasicError(ErrorKind.InvalidArgument, "cron: bad step"))
            }
            step = parsedStep.value()
        }
        Int start = min
        Int end = max
        if base == "*" || base == "?" {
            start = min
            end = max
        } else {
            Int dash = base.indexOf("-")
            if dash >= 0 {
                Result<Int, Error> parsedStart = parseInt(base.substring(0, dash))
                Result<Int, Error> parsedEnd = parseInt(base.substring(dash + 1,
                    base.length() - dash - 1))
                if parsedStart.isErr() || parsedEnd.isErr() {
                    return Err(new BasicError(ErrorKind.InvalidArgument, "cron: bad range"))
                }
                start = parsedStart.value()
                end = parsedEnd.value()
            } else {
                Result<Int, Error> parsed = parseInt(base)
                if parsed.isErr() {
                    return Err(new BasicError(ErrorKind.InvalidArgument, "cron: bad value"))
                }
                start = parsed.value()
                end = start
                if slash >= 0 { end = max }
            }
        }
        if start < min || end > max || start > end {
            return Err(new BasicError(ErrorKind.InvalidArgument, "cron: " + name + " out of range"))
        }
        Int value = start
        while value <= end {
            cronAddUnique(result, value)
            value = value + step
        }
        partIndex = partIndex + 1
    }
    if result.length() == 0 {
        return Err(new BasicError(ErrorKind.InvalidArgument, "cron: empty " + name))
    }
    return Ok(result)
}
