// R4 evidence: calendar day/month/year arithmetic and month-end clamping.
import xdk.time

static Int main() {
    DateTime jan31 = dateTimeOf(2024, 1, 31, 12, 34, 56)
    print(jan31.addMonths(1).format("yyyy-MM-dd HH:mm:ss"))
    print(dateTimeOf(2023, 1, 31, 0, 0, 0).addMonths(1).format("yyyy-MM-dd"))
    print(dateTimeOf(2024, 3, 31, 0, 0, 0).addMonths(-1).format("yyyy-MM-dd"))
    print(dateTimeOf(2024, 12, 31, 0, 0, 0).addMonths(2).format("yyyy-MM-dd"))
    print(dateTimeOf(2024, 2, 29, 0, 0, 0).addYears(1).format("yyyy-MM-dd"))
    print(dateTimeOf(2024, 2, 29, 0, 0, 0).addYears(-1).format("yyyy-MM-dd"))
    print(dateTimeOf(2024, 1, 31, 0, 0, 0).addMonths(-14).format("yyyy-MM-dd"))
    print(dateTimeOf(2024, 1, 31, 0, 0, 0).addMonths(13).format("yyyy-MM-dd"))
    print(dateTimeOf(2024, 2, 28, 0, 0, 0).addDays(1).format("yyyy-MM-dd"))
    print(dateTimeOf(2024, 2, 29, 0, 0, 0).addDays(1).format("yyyy-MM-dd"))
    print(dateTimeOf(2024, 1, 1, 0, 0, 0).addDays(-1).format("yyyy-MM-dd"))
    print(jan31.addYears(1).format("yyyy-MM-dd HH:mm:ss"))
    return 0
}
