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
echo "i18n_panic: PASS"
