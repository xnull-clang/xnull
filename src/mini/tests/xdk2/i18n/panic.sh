#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.i18n
import xdk.i18n
import xdk.errors
import xdk.math

static Int main(String[] args) {
    String name = args.get(0)
    if name == "localeLanguage" {
        Locale value = new Locale("e", "", "")
    } else if name == "localeCountry" {
        Locale value = new Locale("en", "USA", "")
    } else if name == "localeVariant" {
        Locale value = new Locale("en", "US", "12")
    } else if name == "localeRoot" {
        Locale value = new Locale("und", "US", "")
    } else if name == "localeParseNull" {
        Result<Locale, Error> value = Locale.parse(null)
    } else if name == "pluralLocale" {
        PluralRules value = new PluralRules(null)
    } else if name == "pluralNaN" {
        PluralRules rules = new PluralRules(Locale.of("en"))
        String value = rules.category(NaN())
    } else if name == "pluralInf" {
        PluralRules rules = new PluralRules(Locale.of("en"))
        String value = rules.category(Inf())
    } else if name == "pluralForms" {
        PluralRules rules = new PluralRules(Locale.of("en"))
        Result<String, Error> value = rules.select(1.0, null)
    } else if name == "numberLocale" {
        NumberFormat value = new NumberFormat(null, "#,##0")
    } else if name == "numberPatternNull" {
        NumberFormat value = new NumberFormat(Locale.of("en"), null)
    } else if name == "numberEmpty" {
        NumberFormat value = new NumberFormat(Locale.of("en"), "")
    } else if name == "numberNoDigits" {
        NumberFormat value = new NumberFormat(Locale.of("en"), "abc")
    } else if name == "numberDoubleDot" {
        NumberFormat value = new NumberFormat(Locale.of("en"), "0.0.0")
    } else if name == "numberEmptyFraction" {
        NumberFormat value = new NumberFormat(Locale.of("en"), "0.")
    } else if name == "numberGrouping" {
        NumberFormat value = new NumberFormat(Locale.of("en"), "0,00")
    } else if name == "numberFraction" {
        NumberFormat value = new NumberFormat(Locale.of("en"), "0.###################")
    } else if name == "numberWithPattern" {
        NumberFormat format = NumberFormat.decimal(Locale.of("en"))
        NumberFormat value = format.withPattern("bad")
    } else if name == "catalogLocale" {
        MessageCatalog catalog = new MessageCatalog(null)
    } else if name == "catalogParseLocale" {
        Result<MessageCatalog, Error> value = MessageCatalog.parse(null, "a=b")
    } else if name == "catalogParseText" {
        Result<MessageCatalog, Error> value = MessageCatalog.parse(Locale.of("en"), null)
    } else if name == "catalogLoadContext" {
        Result<MessageCatalog, Error> value = MessageCatalog.load(null, Locale.of("en"),
            new Path("/tmp/x"))
    } else if name == "catalogLoadPath" {
        Result<MessageCatalog, Error> value = MessageCatalog.load(Context.background(),
            Locale.of("en"), null)
    } else if name == "catalogReader" {
        Result<MessageCatalog, Error> value = MessageCatalog.loadFromReader(Context.background(),
            Locale.of("en"), null)
    } else if name == "catalogGetKey" {
        MessageCatalog catalog = new MessageCatalog(Locale.of("en"))
        Result<String, Error> value = catalog.get(null)
    } else if name == "catalogGetOr" {
        MessageCatalog catalog = new MessageCatalog(Locale.of("en"))
        String value = catalog.getOr(null, "x")
    } else if name == "catalogMerge" {
        MessageCatalog catalog = new MessageCatalog(Locale.of("en"))
        Result<Int, Error> value = catalog.merge(null, true)
    } else if name == "formatterLocale" {
        MessageFormatter formatter = new MessageFormatter(null)
    } else if name == "formatterTemplate" {
        MessageFormatter formatter = new MessageFormatter(Locale.of("en"))
        Map<String, String> values = [:]
        Result<String, Error> value = formatter.format(null, values)
    } else if name == "formatterValues" {
        MessageFormatter formatter = new MessageFormatter(Locale.of("en"))
        Result<String, Error> value = formatter.format("x", null)
    } else if name == "formatterArgs" {
        MessageFormatter formatter = new MessageFormatter(Locale.of("en"))
        List<String> formatArguments = []
        Result<String, Error> value = formatter.formatArgs(null, formatArguments)
    } else if name == "formatterPlural" {
        MessageFormatter formatter = new MessageFormatter(Locale.of("en"))
        Result<String, Error> value = formatter.plural(1.0, null)
    } else if name == "formatterSelectValue" {
        MessageFormatter formatter = new MessageFormatter(Locale.of("en"))
        Map<String, String> cases = [:]
        Result<String, Error> value = formatter.select(null, cases)
    } else if name == "formatterSelectCases" {
        MessageFormatter formatter = new MessageFormatter(Locale.of("en"))
        Result<String, Error> value = formatter.select("x", null)
    } else if name == "translatorCatalog" {
        Translator translator = new Translator(null)
    } else if name == "translatorKey" {
        MessageCatalog catalog = new MessageCatalog(Locale.of("en"))
        Translator translator = new Translator(catalog)
        Result<String, Error> value = translator.translate(null)
    } else if name == "translatorArgs" {
        MessageCatalog catalog = new MessageCatalog(Locale.of("en"))
        Translator translator = new Translator(catalog)
        Result<String, Error> value = translator.translateWithArgs("k", null)
    } else if name == "translatorLocale" {
        MessageCatalog catalog = new MessageCatalog(Locale.of("en"))
        Translator translator = new Translator(catalog)
        Result<Translator, Error> value = translator.withLocale(null)
    } else if name == "translatorWithCatalog" {
        MessageCatalog catalog = new MessageCatalog(Locale.of("en"))
        Translator translator = new Translator(catalog)
        Translator value = translator.withCatalog(null)
    } else if name == "numberParseNull" {
        NumberFormat format = NumberFormat.decimal(Locale.of("en"))
        Result<Double, Error> value = format.parse(null)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "i18n panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "i18n panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic localeLanguage "Locale: invalid language"
check_panic localeCountry "Locale: invalid country"
check_panic localeVariant "Locale: invalid variant"
check_panic localeRoot "Locale: root locale cannot have country or variant"
check_panic localeParseNull "Locale.parse: null tag"
check_panic pluralLocale "PluralRules: null locale"
check_panic pluralNaN "PluralRules.category: non-finite count"
check_panic pluralInf "PluralRules.category: non-finite count"
check_panic pluralForms "PluralRules.select: null forms"
check_panic numberLocale "NumberFormat: null argument"
check_panic numberPatternNull "NumberFormat: null argument"
check_panic numberEmpty "NumberFormat: empty pattern"
check_panic numberNoDigits "NumberFormat: pattern has no digit placeholder"
check_panic numberDoubleDot "NumberFormat: multiple decimal points"
check_panic numberEmptyFraction "NumberFormat: empty fraction pattern"
check_panic numberGrouping "NumberFormat: invalid grouping"
check_panic numberFraction "NumberFormat: too many fraction digits"
check_panic numberWithPattern "NumberFormat: pattern has no digit placeholder"
check_panic numberParseNull "NumberFormat.parse: null text"
check_panic catalogLocale "MessageCatalog: null locale"
check_panic catalogParseLocale "MessageCatalog.parse: null argument"
check_panic catalogParseText "MessageCatalog.parse: null argument"
check_panic catalogLoadContext "MessageCatalog.load: null argument"
check_panic catalogLoadPath "MessageCatalog.load: null argument"
check_panic catalogReader "MessageCatalog.loadFromReader: null argument"
check_panic catalogGetKey "MessageCatalog.get: null key"
check_panic catalogGetOr "MessageCatalog.getOr: null argument"
check_panic catalogMerge "MessageCatalog.merge: null catalog"
check_panic formatterLocale "MessageFormatter: null locale"
check_panic formatterTemplate "MessageFormatter.format: null argument"
check_panic formatterValues "MessageFormatter.format: null argument"
check_panic formatterArgs "MessageFormatter.formatArgs: null argument"
check_panic formatterPlural "MessageFormatter.plural: null forms"
check_panic formatterSelectValue "MessageFormatter.select: null argument"
check_panic formatterSelectCases "MessageFormatter.select: null argument"
check_panic translatorCatalog "Translator: null catalog"
check_panic translatorKey "Translator.translate: null key"
check_panic translatorArgs "Translator.translateWithArgs: null argument"
check_panic translatorLocale "Translator.withLocale: null locale"
check_panic translatorWithCatalog "Translator.withCatalog: null catalog"
echo "i18n_panic: PASS"
