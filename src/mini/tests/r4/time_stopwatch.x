// R4 evidence: monotonic Stopwatch start/stop/reset/elapsed.
import xdk.time

static Int main() {
    Stopwatch watch = new Stopwatch()
    sleepMs(25)
    Long first = watch.elapsedMs()
    print(first >= 10)
    print(first < 5000)
    print(watch.isRunning())
    Long stopped = watch.stop()
    print(!watch.isRunning())
    sleepMs(20)
    print(watch.elapsedMs() == stopped)
    Long previous = watch.reset()
    print(previous >= 10)
    print(watch.isRunning())
    sleepMs(10)
    print(watch.elapsedMs() >= 5)
    print(watch.elapsed().millis() >= 5)
    return 0
}
