package xdk2.i18n
import xdk.i18n
import xdk.errors
import xdk.math
import xdk.fs

class CatalogReader implements Reader {
    List<String> lines
    Int index

    CatalogReader(List<String> lines) {
        self.lines = lines.copy()
        self.index = 0
    }

    Result<String?, Error> readLine(Context context) {
        if self.index >= self.lines.length() { return Ok(null) }
        String value = self.lines.get(self.index)
        self.index = self.index + 1
        return Ok(value)
    }
}

static String plural(PluralRules rules, Double count) {
    return rules.category(count)
}

static Int main() {
    Context context = Context.background()
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


    String properties = "# comment\n! comment\nwelcome=Hello\nbye: Bye\ncontinued=one\\\ntwo\nescaped=line\\nnext\n"
    Result<MessageCatalog, Error> parsedCatalog = MessageCatalog.parse(Locale.of("en"), properties)
    MessageCatalog catalog = parsedCatalog.value()
    print("catalog-parse=" + str(parsedCatalog.isOk()) + "," + catalog.getOr("welcome", "") +
        "," + catalog.getOr("bye", "") + "," + catalog.getOr("continued", "") + "," +
        str(catalog.getOr("escaped", "").indexOf("\n") >= 0) + "," +
        str(catalog.length()))
    String bomText = "\uFEFFhello=World\n"
    MessageCatalog bomCatalog = MessageCatalog.parse(Locale.of("en"), bomText).value()
    print("catalog-bom=" + bomCatalog.getOr("hello", "") + "," + str(bomCatalog.length()))
    print("catalog-invalid=" + errorKindName(MessageCatalog.parse(Locale.of("en"),
        "a=1\na=2").error().kind()) + "," +
        errorKindName(MessageCatalog.parse(Locale.of("en"), "bad").error().kind()) + "," +
        errorKindName(MessageCatalog.parse(Locale.of("en"), "a=\\q").error().kind()))

    MessageCatalog mutable = new MessageCatalog(Locale.of("en"))
    Result<Unit, Error> addOne = mutable.add("one", "1")
    Result<Unit, Error> addTwo = mutable.add("two", "2")
    Result<Unit, Error> duplicate = mutable.add("one", "x")
    print("catalog-add=" + str(addOne.isOk()) + "," + str(addTwo.isOk()) + "," +
        str(duplicate.isErr()) + "," + str(mutable.has("one")) + "," +
        str(mutable.get("one").value()) + "," + str(mutable.get("missing").isErr()) +
        "," + mutable.getOr("missing", "fallback") + "," + str(mutable.length()))
    MessageCatalog mutableCopy = mutable.copy()
    mutableCopy.add("three", "3")
    print("catalog-copy=" + str(mutable.length()) + "," + str(mutableCopy.length()) + "," +
        str(mutableCopy.remove("two")) + "," + str(mutableCopy.has("two")) + "," +
        str(mutable.remove("missing")))

    MessageCatalog mergeTarget = new MessageCatalog(Locale.of("en"))
    mergeTarget.add("a", "A")
    MessageCatalog mergeSource = new MessageCatalog(Locale.of("en"))
    mergeSource.add("a", "A2")
    mergeSource.add("b", "B")
    Result<Int, Error> conflictMerge = mergeTarget.mergeDefault(mergeSource)
    print("catalog-merge=" + str(conflictMerge.isErr()) + "," +
        str(mergeTarget.has("b")) + "," +
        str(mergeTarget.merge(mergeSource, true).value()) + "," +
        mergeTarget.getOr("a", ""))
    MessageCatalog otherLocale = new MessageCatalog(Locale.of("fr"))
    print("catalog-merge-locale=" + str(mergeTarget.merge(otherLocale, true).isErr()))

    List<String> catalogLines = ["name=Alice", "count={0}"]
    CatalogReader catalogReader = new CatalogReader(catalogLines)
    Result<MessageCatalog, Error> loadedResult = MessageCatalog.loadFromReader(context,
        Locale.of("en"), catalogReader)
    MessageCatalog loaded = loadedResult.value()
    print("catalog-reader=" + str(loadedResult.isOk()) + "," + loaded.getOr("name", "") +
        "," + str(loaded.length()))
    Result<MessageCatalog, Error> missingFile = MessageCatalog.load(context, Locale.of("en"),
        new Path("/tmp/definitely-missing-i18n.properties"))
    print("catalog-load-missing=" + str(missingFile.isErr()))

    MessageFormatter formatter = new MessageFormatter(Locale.of("en"))
    Map<String, String> named = [:]
    named.put("name", "Alice")
    Result<String, Error> formatted = formatter.format("Hello, {name}! {{ok}}", named)
    List<String> args = ["one", "two"]
    Result<String, Error> positional = formatter.formatArgs("{0}-{1}", args)
    Result<String, Error> missingPlaceholder = formatter.format("Hi {missing}", named)
    Result<String, Error> unclosed = formatter.format("Hi {name", named)
    Result<String, Error> unmatched = formatter.format("Hi }", named)
    print("formatter=" + formatted.value() + "," + positional.value() + "," +
        str(missingPlaceholder.isErr()) + "," +
        str(missingPlaceholder.error().describe().indexOf("missing") >= 0) + "," +
        str(unclosed.isErr()) + "," + str(unmatched.isErr()))
    Map<String, String> pluralForms = [:]
    pluralForms.put("one", "one file")
    pluralForms.put("other", "many files")
    Map<String, String> russianForms = [:]
    russianForms.put("one", "one")
    russianForms.put("few", "few")
    russianForms.put("many", "many")
    russianForms.put("other", "other")
    MessageFormatter russianFormatter = new MessageFormatter(Locale.of("ru"))
    print("formatter-plural=" + formatter.plural(1.0, pluralForms).value() + "," +
        formatter.plural(2.0, pluralForms).value() + "," +
        russianFormatter.plural(2.0, russianForms).value() + "," +
        russianFormatter.plural(5.0, russianForms).value())
    Map<String, String> cases = [:]
    cases.put("admin", "Administrator")
    cases.put("other", "User")
    Result<String, Error> selected = formatter.select("admin", cases)
    Result<String, Error> selectedOther = formatter.select("guest", cases)
    Map<String, String> noOther = [:]
    noOther.put("admin", "Administrator")
    print("formatter-select=" + selected.value() + "," + selectedOther.value() + "," +
        str(formatter.select("guest", noOther).isErr()))

    MessageCatalog enCatalog = new MessageCatalog(Locale.of("en"))
    enCatalog.add("welcome", "Hello")
    enCatalog.add("files", "{0} files")
    MessageCatalog ruCatalog = new MessageCatalog(Locale.of("ru"))
    ruCatalog.add("welcome", "Privet")
    Translator translator = new Translator(enCatalog)
    Result<String, Error> translated = translator.translate("welcome")
    List<String> translationArgs = ["3"]
    Result<String, Error> translatedArgs = translator.translateWithArgs("files", translationArgs)
    Translator withRussian = translator.withCatalog(ruCatalog)
    Result<Translator, Error> russianTranslator = withRussian.withLocale(Locale.of("ru"))
    Result<Translator, Error> fallbackTranslator = withRussian.withLocale(Locale.parse("en-AU").value())
    Result<Translator, Error> missingLocale = withRussian.withLocale(Locale.of("de"))
    print("translator=" + translated.value() + "," + translatedArgs.value() + "," +
        russianTranslator.value().translate("welcome").value() + "," +
        fallbackTranslator.value().translate("welcome").value() + "," +
        str(missingLocale.isErr()) + "," + str(translator.translate("missing").isErr()))
    MessageCatalog translatorCatalog = translator.catalog()
    translatorCatalog.add("extra", "x")
    print("translator-copy=" + str(translatorCatalog.has("extra")) + "," +
        str(translator.catalog().has("extra")) + "," +
        translator.locale().toString())
    return 0
}
