// R4 evidence: the retained DateTime add/diff subset for the optimized
// "calendar add/sub boundary" item. This is not full civil arithmetic:
// month/year arithmetic and DST are deliberately absent (see R4-EVIDENCE.md).
import xdk.time

static Int main() {
    DateTime jan31 = dateTimeOf(2024, 1, 31, 23, 59, 59)
    print(jan31.format("yyyy-MM-dd HH:mm:ss"))
    print(jan31.format("MM|MMM|MMMM"))
    print(jan31.format("dd|ddd|dddd"))
    print(jan31.format("EEE|EEEE"))
    print(jan31.format("EEE, dd MMM yyyy"))
    DateTime feb01 = jan31.add(durationOfDays(1))
    print(feb01.format("yyyy-MM-dd HH:mm:ss"))
    print(feb01.timestamp() - jan31.timestamp())
    print(jan31.diff(feb01).millis())
    print(jan31.before(feb01))
    print(jan31.after(feb01))
    print(jan31.compare(feb01))
    print(jan31.weekday())
    print(jan31.dayOfYear())

    DateTime leap = dateTimeOf(2024, 2, 29, 0, 0, 0)
    DateTime march = leap.add(durationOfDays(1))
    print(march.format("yyyy-MM-dd"))
    DateTime nonLeap = dateTimeOf(2023, 2, 28, 0, 0, 0)
    print(nonLeap.add(durationOfDays(1)).format("yyyy-MM-dd"))

    DateTime epoch = dateTimeFromTimestamp(0)
    print(epoch.format("yyyy-MM-dd HH:mm:ss"))
    print(epoch.add(durationOfMillis(1500)).format("yyyy-MM-dd HH:mm:ss.SSS"))
    print(epoch.add(durationOfMillis(-1)).timestamp())
    return 0
}
