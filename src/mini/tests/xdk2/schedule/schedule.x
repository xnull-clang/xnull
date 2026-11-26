package xdk2.schedule
import xdk.schedule
import xdk.time
import xdk.errors

class CounterJob implements Job {
    Int runs
    CounterJob() { self.runs = 0 }
    Result<Unit, Error> run(Context context) {
        self.runs = self.runs + 1
        return Ok()
    }
}

static Int main() {
    Long base = 1704067200000 as Long
    TimeZone utc = TimeZone.utc()
    print("kind=" + scheduleKindName(ScheduleKind.Once) + "," +
        scheduleKindName(ScheduleKind.FixedRate) + "," +
        scheduleKindName(ScheduleKind.FixedDelay) + "," +
        scheduleKindName(ScheduleKind.Cron))
    print("misfire=" + misfirePolicyName(MisfirePolicy.Skip) + "," +
        misfirePolicyName(MisfirePolicy.FireOnce) + "," +
        misfirePolicyName(MisfirePolicy.CatchUp))

    Result<CronExpression, Error> everyFive = CronExpression.parse("*/5 * * * *")
    CronExpression cron = everyFive.value()
    print("cron-parse=" + cron.text() + "," + cron.describe())
    Long next = cron.next(base + 60000 as Long, utc).value()
    print("cron-next=" + str(next) + "," + str(next == 1704067500000 as Long))
    print("cron-matches=" + str(cron.matches(1704067500000 as Long, utc)) + "," +
        str(cron.matches(1704067530000 as Long, utc)) + "," +
        str(cron.matches(1704067560000 as Long, utc)))
    List<Long> nextValues = cron.nextN(base + 60000 as Long, utc, 3).value()
    print("cron-nextN=" + str(nextValues.length()) + "," + str(nextValues.get(0)) + "," +
        str(nextValues.get(1)) + "," + str(nextValues.get(2)))

    CronExpression hourly = CronExpression.parse("0 2 * * *").value()
    print("cron-daily=" + str(hourly.next(base, utc).value()) + "," +
        str(hourly.next(base, utc).value() == 1704074400000 as Long))
    CronExpression monthly = CronExpression.parse("0 0 1 * *").value()
    Long jan15 = base + (14 as Long) * 86400000 as Long
    print("cron-month=" + str(monthly.next(jan15, utc).value()) + "," +
        str(monthly.next(jan15, utc).value() == 1706745600000 as Long))
    CronExpression sunday = CronExpression.parse("0 0 * * 0").value()
    print("cron-dow=" + str(sunday.next(base, utc).value()) + "," +
        str(sunday.next(base, utc).value() == 1704585600000 as Long))
    TimeZone east = TimeZone.fixed(28800000)
    CronExpression midnight = CronExpression.parse("0 0 * * *").value()
    print("cron-zone=" + str(midnight.next(base, east).value()) + "," +
        str(midnight.next(base, east).value() == 1704124800000 as Long))

    print("cron-invalid=" + str(CronExpression.parse("61 * * * *").isErr()) + "," +
        str(CronExpression.parse("* *").isErr()) + "," +
        str(CronExpression.parse("* * * * 9").isErr()) + "," +
        str(CronExpression.parse("a * * * *").isErr()) + "," +
        str(CronExpression.parse("*/0 * * * *").isErr()))

    Schedule once = Schedule.once(50 as Long)
    Schedule absolute = Schedule.at(1234 as Long)
    Schedule rate = Schedule.fixedRate(100 as Long)
    Schedule rateInitial = Schedule.fixedRateWithDelay(10 as Long, 100 as Long)
    Schedule delay = Schedule.fixedDelay(100 as Long)
    Schedule delayInitial = Schedule.fixedDelayWithDelay(10 as Long, 100 as Long)
    Schedule cronSchedule = Schedule.cronExpressionOf(cron)
    print("schedule=" + scheduleKindName(once.kind()) + "," + str(once.delayMillis()) +
        "," + str(absolute.atEpochMillis()) + "," + str(absolute.isAbsolute()) + "," +
        str(rate.periodMillis()) + "," + str(rateInitial.initialDelayMillis()) + "," +
        str(delay.periodMillis()) + "," + str(delayInitial.initialDelayMillis()) + "," +
        scheduleKindName(cronSchedule.kind()) + "," + str(cronSchedule.cronExpression() != null))
    print("schedule-text=" + once.describe() + "|" + rateInitial.describe() + "|" +
        delayInitial.describe() + "|" + cronSchedule.describe())

    SchedulerOptions options = new SchedulerOptions()
    print("options=" + str(options.getWorkerCount()) + "," + str(options.getMaxPending()) +
        "," + misfirePolicyName(options.getMisfirePolicy()) + "," +
        options.getDefaultTimeZone().id() + "," + str(options.getShutdownTimeoutMillis()) +
        "," + str(options.getCatchUpLimit()))
    SchedulerOptions copy = options.copy()
    copy.workerCount(3)
    copy.maxPending(7)
    copy.catchUpLimit(2)
    print("options-copy=" + str(options.getWorkerCount()) + "," +
        str(copy.getWorkerCount()) + "," + str(options.getMaxPending()) + "," +
        str(copy.getMaxPending()) + "," + str(options.getCatchUpLimit()) + "," +
        str(copy.getCatchUpLimit()))

    Scheduler scheduler = Scheduler.create(options)
    CounterJob fixedJob = new CounterJob()
    Schedule fixedSchedule = Schedule.fixedDelay(50 as Long)
    Result<JobHandle, Error> fixedHandle = scheduler.schedule(fixedJob, fixedSchedule)
    JobHandle fixedJobHandle = fixedHandle.value()
    String fixedHandleText = fixedJobHandle.describe()
    print("sched-schedule=" + str(fixedHandle.isOk()) + "," + str(scheduler.jobs().length()) +
        "," + str(fixedHandleText.length()) + "," +
        str(scheduler.options().getMaxPending()))
    sleepMs(190 as Long)
    Int beforeCancel = fixedJob.runs
    Bool cancelled = scheduler.cancel(fixedJobHandle)
    sleepMs(130 as Long)
    Int afterCancel = fixedJob.runs
    print("sched-fixed=" + str(beforeCancel >= 2) + "," + str(cancelled) + "," +
        str(afterCancel >= beforeCancel) + "," + str(afterCancel <= beforeCancel + 1) +
        "," + str(scheduler.cancel(fixedJobHandle)))

    CounterJob triggerJob = new CounterJob()
    Result<JobHandle, Error> triggerHandle = scheduler.schedule(triggerJob,
        Schedule.fixedDelayWithDelay(60000 as Long, 60000 as Long))
    Result<Unit, Error> triggered = scheduler.trigger(triggerHandle.value())
    print("sched-trigger=" + str(triggered.isOk()) + "," + str(triggerJob.runs))

    CounterJob cronJob = new CounterJob()
    Result<JobHandle, Error> cronHandle = scheduler.schedule(cronJob,
        Schedule.cronExpressionOf(CronExpression.parse("*/5 * * * *").value()))
    JobHandle cronJobHandle = cronHandle.value()
    Result<Unit, Error> cronTrigger = scheduler.trigger(cronJobHandle)
    Schedule cronJobSchedule = cronJobHandle.schedule()
    print("sched-cron=" + str(cronTrigger.isOk()) + "," + str(cronJob.runs) + "," +
        scheduleKindName(cronJobSchedule.kind()))

    Result<Unit, Error> shutdown = scheduler.shutdown(Context.background())
    Result<Unit, Error> shutdownAgain = scheduler.shutdown(Context.background())
    Result<JobHandle, Error> afterShutdown = scheduler.schedule(new CounterJob(),
        Schedule.once(10 as Long))
    print("sched-shutdown=" + str(shutdown.isOk()) + "," + str(shutdownAgain.isOk()) +
        "," + str(scheduler.isShutdown()) + "," +
        errorKindName(afterShutdown.error().kind()) + "," +
        errorKindName(scheduler.trigger(triggerHandle.value()).error().kind()))

    SchedulerOptions smallOptions = new SchedulerOptions()
    smallOptions.maxPending(1)
    Scheduler smallScheduler = Scheduler.create(smallOptions)
    Result<JobHandle, Error> firstJob = smallScheduler.schedule(new CounterJob(),
        Schedule.fixedDelay(1000 as Long))
    Result<JobHandle, Error> secondJob = smallScheduler.schedule(new CounterJob(),
        Schedule.fixedDelay(1000 as Long))
    print("sched-max=" + str(firstJob.isOk()) + "," + str(secondJob.isErr()) + "," +
        errorKindName(secondJob.error().kind()))
    smallScheduler.shutdown(Context.background())
    return 0
}
