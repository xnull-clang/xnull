#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.schedule
import xdk.schedule
import xdk.time
import xdk.errors

class NullJob implements Job {
    Result<Unit, Error> run(Context context) { return Ok() }
}

static Int main(String[] args) {
    String name = args.get(0)
    if name == "onceNegative" {
        Schedule value = Schedule.once(-1 as Long)
    } else if name == "rateZero" {
        Schedule value = Schedule.fixedRate(0 as Long)
    } else if name == "delayZero" {
        Schedule value = Schedule.fixedDelay(0 as Long)
    } else if name == "cronInvalid" {
        Schedule value = Schedule.cron("bad")
    } else if name == "cronNull" {
        Schedule value = Schedule.cronExpressionOf(null)
    } else if name == "optionsWorker" {
        SchedulerOptions options = new SchedulerOptions()
        options.workerCount(0)
    } else if name == "optionsPending" {
        SchedulerOptions options = new SchedulerOptions()
        options.maxPending(0)
    } else if name == "optionsZone" {
        SchedulerOptions options = new SchedulerOptions()
        options.defaultTimeZone(null)
    } else if name == "optionsCatchUp" {
        SchedulerOptions options = new SchedulerOptions()
        options.catchUpLimit(-1)
    } else if name == "handleId" {
        JobHandle handle = new JobHandle(-1 as Long, "job", Schedule.once(1 as Long), false)
    } else if name == "handleName" {
        JobHandle handle = new JobHandle(1 as Long, "", Schedule.once(1 as Long), false)
    } else if name == "handleSchedule" {
        JobHandle handle = new JobHandle(1 as Long, "job", null, false)
    } else if name == "createNull" {
        Scheduler scheduler = Scheduler.create(null)
    } else if name == "scheduleJob" {
        Scheduler scheduler = Scheduler.create(new SchedulerOptions())
        Result<JobHandle, Error> value = scheduler.schedule(null, Schedule.once(1 as Long))
    } else if name == "scheduleSpec" {
        Scheduler scheduler = Scheduler.create(new SchedulerOptions())
        Result<JobHandle, Error> value = scheduler.schedule(new NullJob(), null)
    } else if name == "cancelNull" {
        Scheduler scheduler = Scheduler.create(new SchedulerOptions())
        Bool value = scheduler.cancel(null)
    } else if name == "triggerNull" {
        Scheduler scheduler = Scheduler.create(new SchedulerOptions())
        Result<Unit, Error> value = scheduler.trigger(null)
    } else if name == "shutdownNull" {
        Scheduler scheduler = Scheduler.create(new SchedulerOptions())
        Result<Unit, Error> value = scheduler.shutdown(null)
    } else if name == "nextZone" {
        CronExpression cron = CronExpression.parse("*/5 * * * *").value()
        Result<Long, Error> value = cron.next(0 as Long, null)
    } else if name == "matchesZone" {
        CronExpression cron = CronExpression.parse("*/5 * * * *").value()
        Bool value = cron.matches(0 as Long, null)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "schedule panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "schedule panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic onceNegative "Schedule.once: negative delay"
check_panic rateZero "Schedule.fixedRate: invalid period"
check_panic delayZero "Schedule.fixedDelay: invalid delay"
check_panic cronInvalid "Schedule.cron: invalid expression"
check_panic cronNull "Schedule.cronExpressionOf: null"
check_panic optionsWorker "SchedulerOptions.workerCount: < 1"
check_panic optionsPending "SchedulerOptions.maxPending: < 1"
check_panic optionsZone "SchedulerOptions.defaultTimeZone: null"
check_panic optionsCatchUp "SchedulerOptions.catchUpLimit: negative"
check_panic handleId "JobHandle: invalid field"
check_panic handleName "JobHandle: invalid field"
check_panic handleSchedule "JobHandle: invalid field"
check_panic createNull "Scheduler.create: null options"
check_panic scheduleJob "Scheduler.schedule: null argument"
check_panic scheduleSpec "Scheduler.schedule: null argument"
check_panic cancelNull "Scheduler.cancel: null handle"
check_panic triggerNull "Scheduler.trigger: null handle"
check_panic shutdownNull "Scheduler.shutdown: null context"
check_panic nextZone "CronExpression.next: null zone"
check_panic matchesZone "CronExpression.matches: null zone"
echo "schedule_panic: PASS"
