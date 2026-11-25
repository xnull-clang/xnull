package xdk2.i18n
import xdk.i18n
import xdk.errors
import xdk.math

static String plural(PluralRules rules, Double count) {
    return rules.category(count)
}

static Int main() {
    Locale en = Locale.parse("en-us").value()
    Locale de = Locale.parse("de_CH_1901").value()
    Locale es = Locale.parse("es-419").value()
    Locale root = Locale.root()
    print("locale=" + en.toString() + "," + de.toString() + "," + es.toString() + "," +
        root.toString() + "," + str(root.isRoot()) + "," + en.language() + "," +
        en.country() + "," + de.variant())
    print("locale-parse=" + str(Locale.parse("").isErr()) + "," +
        str(Locale.parse("zh-Hans-CN").isErr()) + "," +
        str(Locale.parse("e").isErr()) + "," +
        str(Locale.parse("en-USA").isErr()) + "," +
        str(Locale.parse("en-US-").isErr()))
    Locale enUpper = Locale.parse("EN-us").value()
    print("locale-equals=" + str(en.equals(enUpper)) + "," + str(en.equals(null)) + "," +
        str(Locale.of("fr").toString()) + "," +
        Locale.ofWithCountry("pt", "BR").toString())

    PluralRules english = new PluralRules(Locale.of("en"))
    PluralRules french = new PluralRules(Locale.of("fr"))
    PluralRules russian = new PluralRules(Locale.of("ru"))
    PluralRules polish = new PluralRules(Locale.of("pl"))
    PluralRules arabic = new PluralRules(Locale.of("ar"))
    PluralRules japanese = new PluralRules(Locale.of("ja"))
    PluralRules unknown = new PluralRules(Locale.of("xx"))
    print("plural-en=" + plural(english, 0.0) + "," + plural(english, 1.0) + "," +
        plural(english, 2.0) + "," + plural(english, 1.5) + "," +
        plural(english, -1.0))
    print("plural-fr=" + plural(french, 0.0) + "," + plural(french, 1.0) + "," +
        plural(french, 1.5) + "," + plural(french, 2.0))
    print("plural-ru=" + plural(russian, 1.0) + "," + plural(russian, 2.0) + "," +
        plural(russian, 4.0) + "," + plural(russian, 5.0) + "," +
        plural(russian, 11.0) + "," + plural(russian, 21.0) + "," +
        plural(russian, 22.0) + "," + plural(russian, 25.0) + "," +
        plural(russian, 1.5))
    print("plural-pl=" + plural(polish, 1.0) + "," + plural(polish, 2.0) + "," +
        plural(polish, 5.0) + "," + plural(polish, 12.0) + "," +
        plural(polish, 22.0))
    print("plural-ar=" + plural(arabic, 0.0) + "," + plural(arabic, 1.0) + "," +
        plural(arabic, 2.0) + "," + plural(arabic, 3.0) + "," +
        plural(arabic, 11.0) + "," + plural(arabic, 100.0))
    print("plural-other=" + plural(japanese, 1.0) + "," + plural(japanese, 2.0) + "," +
        plural(unknown, 1.0) + "," + plural(unknown, 2.0))

    Map<String, String> forms = ["one":"ONE", "few":"FEW", "many":"MANY", "other":"OTHER"]
    Result<String, Error> oneForm = russian.select(1.0, forms)
    Result<String, Error> fewForm = russian.select(2.0, forms)
    Map<String, String> fallbackForms = ["other":"OTHER"]
    Result<String, Error> fallback = russian.select(1.0, fallbackForms)
    Map<String, String> missingForms = ["one":"ONE"]
    Result<String, Error> missing = russian.select(2.0, missingForms)
    print("plural-select=" + oneForm.value() + "," + fewForm.value() + "," +
        fallback.value() + "," + str(missing.isErr()) + "," +
        errorKindName(missing.error().kind()))

    NumberFormat enFormat = NumberFormat.ofPattern(en, "#,##0.00")
    Locale deNumber = Locale.ofWithCountry("de", "DE")
    NumberFormat deFormat = NumberFormat.ofPattern(deNumber, "#,##0.00")
    NumberFormat frFormat = NumberFormat.ofPattern(Locale.of("fr"), "#,##0.00")
    NumberFormat ruFormat = NumberFormat.ofPattern(Locale.of("ru"), "#,##0.00")
    print("number=" + enFormat.formatDouble(12345.678) + "," +
        deFormat.formatDouble(12345.678) + "," + frFormat.formatDouble(12345.678) +
        "," + ruFormat.formatDouble(12345.678) + "," +
        enFormat.formatLong(42 as Long) + "," + enFormat.formatLong(-1234 as Long))
    NumberFormat decimal = NumberFormat.decimal(en)
    print("number-decimal=" + decimal.formatDouble(1234.5) + "," +
        decimal.formatDouble(0.0) + "," + decimal.formatDouble(2.0) + "," +
        decimal.pattern() + "," + decimal.groupingSeparator() + "," +
        decimal.decimalSeparator())
    print("number-special=" + enFormat.formatDouble(NaN()) + "," +
        enFormat.formatDouble(Inf()) + "," + enFormat.formatDouble(0.0 - Inf()) + "," +
        enFormat.formatDouble(1.005) + "," + enFormat.formatDouble(0.0))
    Result<Double, Error> parsedEn = enFormat.parse("12,345.68")
    Result<Double, Error> parsedDe = deFormat.parse("12.345,68")
    Result<Double, Error> parsedFr = frFormat.parse("12 345,68")
    print("number-parse=" + str(parsedEn.isOk()) + "," + enFormat.formatDouble(parsedEn.value()) +
        "," + str(parsedDe.isOk()) + "," + deFormat.formatDouble(parsedDe.value()) + "," +
        str(parsedFr.isOk()) + "," + frFormat.formatDouble(parsedFr.value()))
    print("number-invalid=" + errorKindName(enFormat.parse("abc").error().kind()) + "," +
        errorKindName(enFormat.parse("1,23,456").error().kind()) + "," +
        errorKindName(enFormat.parse("").error().kind()) + "," +
        errorKindName(enFormat.parse("1.2.3").error().kind()))
    NumberFormat plain = enFormat.withPattern("0")
    print("number-pattern=" + plain.formatDouble(7.6) + "," + plain.pattern() + "," +
        str(plain.locale().toString() == en.toString()))

    return 0
}
