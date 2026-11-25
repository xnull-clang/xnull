// xdk.i18n —— Locale/PluralRules/NumberFormat 核心（M21.6）
//
// CLDR 子集：仅列出的语言规则与数字格式；不做脚本/扩展段/全量 CLDR。
// 稳定性：preview。合同见 docs/design/utils/i18n/。
package xdk.i18n
import xdk.errors
import xdk.math
import xdk.text

// ---------- Locale ----------
class Locale {
    final String _language
    final String _country
    final String _variant

    Locale(String language, String country, String variant) {
        if language == null || country == null || variant == null {
            throw "Locale: null argument"
        }
        String normalizedLanguage = language.trim().toLower()
        String normalizedCountry = country.trim().toUpper()
        String normalizedVariant = variant.trim().toUpper()
        if !Locale.isValidLanguage(normalizedLanguage) {
            throw "Locale: invalid language"
        }
        if !Locale.isValidCountry(normalizedCountry) {
            throw "Locale: invalid country"
        }
        if !Locale.isValidVariant(normalizedVariant) {
            throw "Locale: invalid variant"
        }
        if normalizedLanguage == "und" &&
            (normalizedCountry != "" || normalizedVariant != "") {
            throw "Locale: root locale cannot have country or variant"
        }
        self._language = normalizedLanguage
        self._country = normalizedCountry
        self._variant = normalizedVariant
    }

    static Locale of(String language) {
        return new Locale(language, "", "")
    }

    static Locale ofWithCountry(String language, String country) {
        return new Locale(language, country, "")
    }

    static Locale root() { return new Locale("und", "", "") }

    static Result<Locale, Error> parse(String tag) {
        if tag == null { throw "Locale.parse: null tag" }
        String normalized = tag.trim()
        if normalized == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "empty locale tag"))
        }
        normalized = normalized.replace("_", "-")
        List<String> parts = normalized.split("-")
        if parts.length() == 0 || parts.length() > 3 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "locale extensions are not supported"))
        }
        String language = parts.get(0).trim().toLower()
        if !Locale.isValidLanguage(language) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid language: " + language))
        }
        if language == "und" && parts.length() > 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "root locale cannot have subtags"))
        }
        String country = ""
        String variant = ""
        if parts.length() == 2 {
            String second = parts.get(1).trim()
            if second == "" {
                return Err(new BasicError(ErrorKind.InvalidArgument, "empty locale subtag"))
            }
            String upper = second.toUpper()
            if Locale.isValidCountry(upper) && upper != "" {
                country = upper
            } else if Locale.isValidVariant(upper) && upper != "" {
                variant = upper
            } else {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "invalid locale subtag: " + second))
            }
        }
        if parts.length() == 3 {
            String second = parts.get(1).trim().toUpper()
            String third = parts.get(2).trim().toUpper()
            if second == "" || third == "" || !Locale.isValidCountry(second) ||
                second == "" || !Locale.isValidVariant(third) || third == "" {
                return Err(new BasicError(ErrorKind.InvalidArgument, "invalid locale subtag"))
            }
            country = second
            variant = third
        }
        return Ok(new Locale(language, country, variant))
    }

    String language() { return self._language }
    String country() { return self._country }
    String variant() { return self._variant }
    Bool isRoot() { return self._language == "und" }

    Bool equals(Locale other) {
        if other == null { return false }
        return self._language == other.language() &&
            self._country == other.country() &&
            self._variant == other.variant()
    }

    String toString() {
        if self.isRoot() { return "und" }
        String result = self._language
        if self._country != "" { result = result + "-" + self._country }
        if self._variant != "" { result = result + "-" + self._variant }
        return result
    }

    static Bool isValidLanguage(String value) {
        if value == "und" { return true }
        if value.length() < 2 || value.length() > 3 { return false }
        Int index = 0
        while index < value.length() {
            Int code = value.get(index)
            if !isLowerAscii(code) { return false }
            index = index + 1
        }
        return true
    }

    static Bool isValidCountry(String value) {
        if value == "" { return true }
        if value.length() == 2 {
            Int index = 0
            while index < value.length() {
                Int code = value.get(index)
                if !isUpperAscii(code) { return false }
                index = index + 1
            }
            return true
        }
        if value.length() == 3 {
            Int index = 0
            while index < value.length() {
                Int code = value.get(index)
                if code < 48 || code > 57 { return false }
                index = index + 1
            }
            return true
        }
        return false
    }

    static Bool isValidVariant(String value) {
        if value == "" { return true }
        if value.length() < 4 || value.length() > 8 { return false }
        Int index = 0
        while index < value.length() {
            Int code = value.get(index)
            Bool digit = code >= 48 && code <= 57
            Bool upper = isUpperAscii(code)
            if !digit && !upper { return false }
            index = index + 1
        }
        if value.length() == 4 {
            Int code = value.get(0)
            if code < 48 || code > 57 { return false }
        }
        return true
    }
}

static Bool isLowerAscii(Int code) { return code >= 97 && code <= 122 }
static Bool isUpperAscii(Int code) { return code >= 65 && code <= 90 }

// ---------- PluralRules ----------
class PluralRules {
    final Locale _locale

    PluralRules(Locale locale) {
        if locale == null { throw "PluralRules: null locale" }
        self._locale = locale
    }

    Locale locale() { return self._locale }

    String category(Double count) {
        if isNaN(count) || isInf(count) {
            throw "PluralRules.category: non-finite count"
        }
        Double value = count
        if value < 0.0 { value = 0.0 - value }
        String language = self._locale.language()
        if language == "ru" || language == "uk" {
            return self.slavic(value)
        }
        if language == "pl" {
            return self.polish(value)
        }
        if language == "ar" {
            return self.arabic(value)
        }
        if language == "fr" {
            Double integerPart = (value as Long) as Double
            if integerPart == 0.0 || integerPart == 1.0 { return "one" }
            return "other"
        }
        if language == "ja" || language == "ko" || language == "zh" ||
            language == "th" || language == "vi" || language == "id" ||
            language == "ms" || language == "tr" {
            return "other"
        }
        if language == "en" || language == "de" || language == "es" ||
            language == "it" || language == "pt" || language == "nl" ||
            language == "sv" {
            if value == 1.0 { return "one" }
            return "other"
        }
        return "other"
    }

    Result<String, Error> select(Double count, Map<String, String> forms) {
        if forms == null { throw "PluralRules.select: null forms" }
        String category = self.category(count)
        if forms.has(category) { return Ok(forms.getOr(category, "")) }
        if forms.has("other") { return Ok(forms.getOr("other", "")) }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "missing plural form: " + category))
    }

    private String slavic(Double value) {
        if ((value as Long) as Double) != value { return "other" }
        if value >= 9223372036854775808.0 { return "many" }
        Long number = value as Long
        Long mod10 = number % (10 as Long)
        Long mod100 = number % (100 as Long)
        if mod10 == 1 as Long && mod100 != 11 as Long { return "one" }
        if mod10 >= 2 as Long && mod10 <= 4 as Long &&
            (mod100 < 12 as Long || mod100 > 14 as Long) { return "few" }
        return "many"
    }

    private String polish(Double value) {
        if ((value as Long) as Double) != value { return "other" }
        if value >= 9223372036854775808.0 { return "many" }
        Long number = value as Long
        if number == 1 as Long { return "one" }
        Long mod10 = number % (10 as Long)
        Long mod100 = number % (100 as Long)
        if mod10 >= 2 as Long && mod10 <= 4 as Long &&
            (mod100 < 12 as Long || mod100 > 14 as Long) { return "few" }
        return "many"
    }

    private String arabic(Double value) {
        if ((value as Long) as Double) != value { return "other" }
        if value >= 9223372036854775808.0 { return "other" }
        Long number = value as Long
        if number == 0 as Long { return "zero" }
        if number == 1 as Long { return "one" }
        if number == 2 as Long { return "two" }
        Long mod100 = number % (100 as Long)
        if mod100 >= 3 as Long && mod100 <= 10 as Long { return "few" }
        if mod100 >= 11 as Long && mod100 <= 99 as Long { return "many" }
        return "other"
    }
}

// ---------- NumberFormat ----------
class NumberFormat {
    final Locale _locale
    final String _pattern
    final String _prefix
    final String _suffix
    final Int _minIntegerDigits
    final Int _minFractionDigits
    final Int _maxFractionDigits
    final Bool _grouping
    final String _groupingSeparator
    final String _decimalSeparator

    NumberFormat(Locale locale, String pattern) {
        if locale == null || pattern == null {
            throw "NumberFormat: null argument"
        }
        if pattern == "" { throw "NumberFormat: empty pattern" }
        Int first = -1
        Int last = -1
        Int index = 0
        while index < pattern.length() {
            Int code = pattern.get(index)
            if code == 48 || code == 35 {
                if first < 0 { first = index }
                last = index
            }
            index = index + 1
        }
        if first < 0 { throw "NumberFormat: pattern has no digit placeholder" }
        String prefix = pattern.substring(0, first)
        String suffix = pattern.substring(last + 1, pattern.length() - last - 1)
        if suffix == "." { throw "NumberFormat: empty fraction pattern" }
        if NumberFormat.affixInvalid(prefix) || NumberFormat.affixInvalid(suffix) {
            throw "NumberFormat: invalid affix"
        }
        String body = pattern.substring(first, last - first + 1)
        Int dot = body.indexOf(".")
        if dot >= 0 && body.substring(dot + 1, body.length() - dot - 1).indexOf(".") >= 0 {
            throw "NumberFormat: multiple decimal points"
        }
        String integerPattern = body
        String fractionPattern = ""
        if dot >= 0 {
            integerPattern = body.substring(0, dot)
            fractionPattern = body.substring(dot + 1, body.length() - dot - 1)
            if fractionPattern == "" {
                throw "NumberFormat: empty fraction pattern"
            }
        }
        if integerPattern == "" { throw "NumberFormat: empty integer pattern" }
        Int minInteger = 0
        Bool grouping = false
        Int integerIndex = 0
        while integerIndex < integerPattern.length() {
            Int code = integerPattern.get(integerIndex)
            if code == 48 { minInteger = minInteger + 1 }
            else if code == 44 { grouping = true }
            else if code != 35 { throw "NumberFormat: invalid integer pattern" }
            integerIndex = integerIndex + 1
        }
        if minInteger < 1 { minInteger = 1 }
        if grouping && !NumberFormat.validGrouping(integerPattern) {
            throw "NumberFormat: invalid grouping"
        }
        Int minFraction = 0
        Int maxFraction = 0
        Int fractionIndex = 0
        while fractionIndex < fractionPattern.length() {
            Int code = fractionPattern.get(fractionIndex)
            if code == 48 {
                minFraction = minFraction + 1
                maxFraction = maxFraction + 1
            } else if code == 35 {
                maxFraction = maxFraction + 1
            } else {
                throw "NumberFormat: invalid fraction pattern"
            }
            fractionIndex = fractionIndex + 1
        }
        if maxFraction > 18 { throw "NumberFormat: too many fraction digits" }
        self._locale = locale
        self._pattern = pattern
        self._prefix = prefix
        self._suffix = suffix
        self._minIntegerDigits = minInteger
        self._minFractionDigits = minFraction
        self._maxFractionDigits = maxFraction
        self._grouping = grouping
        self._groupingSeparator = NumberFormat.groupingSeparatorFor(locale)
        self._decimalSeparator = NumberFormat.decimalSeparatorFor(locale)
    }

    static NumberFormat ofPattern(Locale locale, String pattern) {
        return new NumberFormat(locale, pattern)
    }

    static NumberFormat decimal(Locale locale) {
        if locale == null { throw "NumberFormat.decimal: null locale" }
        return new NumberFormat(locale, "#,##0.###")
    }

    Locale locale() { return self._locale }
    String pattern() { return self._pattern }
    String groupingSeparator() { return self._groupingSeparator }
    String decimalSeparator() { return self._decimalSeparator }

    NumberFormat withPattern(String pattern) {
        return new NumberFormat(self._locale, pattern)
    }

    String formatLong(Long value) {
        String digits = str(value)
        Bool negative = false
        if value < 0 as Long {
            negative = true
            digits = digits.substring(1, digits.length() - 1)
        }
        String integerPart = digits
        String fractionPart = ""
        if self._minFractionDigits > 0 {
            fractionPart = terminalPad("0", self._minFractionDigits)
        }
        return self.assemble(negative, integerPart, fractionPart)
    }

    String formatDouble(Double value) {
        if isNaN(value) { return "NaN" }
        if isInf(value) {
            if value < 0.0 { return "-∞" }
            return "∞"
        }
        Bool negative = value < 0.0
        Double absolute = value
        if negative { absolute = 0.0 - absolute }
        Long factor = 1 as Long
        Int index = 0
        while index < self._maxFractionDigits {
            factor = factor * (10 as Long)
            index = index + 1
        }
        Double scaledValue = absolute * (factor as Double)
        Long rounded = (scaledValue + 0.5000001) as Long
        Long integerValue = rounded / factor
        Long fractionValue = rounded % factor
        String integerPart = str(integerValue)
        String fractionPart = ""
        if self._maxFractionDigits > 0 {
            fractionPart = str(fractionValue)
            while fractionPart.length() < self._maxFractionDigits {
                fractionPart = "0" + fractionPart
            }
            while fractionPart.length() > self._minFractionDigits &&
                fractionPart.substring(fractionPart.length() - 1, 1) == "0" {
                fractionPart = fractionPart.substring(0, fractionPart.length() - 1)
            }
        }
        return self.assemble(negative, integerPart, fractionPart)
    }

    Result<Double, Error> parse(String text) {
        if text == null { throw "NumberFormat.parse: null text" }
        String value = text.trim()
        if self._prefix != "" && value.startsWith(self._prefix) {
            value = value.substring(self._prefix.length(), value.length() - self._prefix.length())
        }
        if self._suffix != "" && value.endsWith(self._suffix) {
            value = value.substring(0, value.length() - self._suffix.length())
        }
        Bool negative = false
        if value.startsWith("+") {
            value = value.substring(1, value.length() - 1)
        } else if value.startsWith("-") {
            negative = true
            value = value.substring(1, value.length() - 1)
        }
        if value == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "number: empty"))
        }
        Int decimalPosition = value.indexOf(self._decimalSeparator)
        String integerPart = value
        String fractionPart = ""
        if decimalPosition >= 0 {
            if value.substring(decimalPosition + self._decimalSeparator.length(),
                value.length() - decimalPosition - self._decimalSeparator.length())
                .indexOf(self._decimalSeparator) >= 0 {
                return Err(new BasicError(ErrorKind.InvalidArgument, "number: multiple decimals"))
            }
            integerPart = value.substring(0, decimalPosition)
            fractionPart = value.substring(decimalPosition + self._decimalSeparator.length(),
                value.length() - decimalPosition - self._decimalSeparator.length())
        }
        if self._grouping && integerPart.indexOf(self._groupingSeparator) >= 0 {
            if !NumberFormat.validGroupedDigits(integerPart, self._groupingSeparator) {
                return Err(new BasicError(ErrorKind.InvalidArgument, "number: bad grouping"))
            }
            integerPart = integerPart.replace(self._groupingSeparator, "")
        }
        if integerPart == "" || !NumberFormat.digitsOnly(integerPart) ||
            (fractionPart != "" && !NumberFormat.digitsOnly(fractionPart)) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "number: invalid digits"))
        }
        Double result = 0.0
        Int digitIndex = 0
        while digitIndex < integerPart.length() {
            result = result * 10.0 + (integerPart.get(digitIndex) - 48) as Double
            digitIndex = digitIndex + 1
        }
        Double divisor = 1.0
        digitIndex = 0
        while digitIndex < fractionPart.length() {
            divisor = divisor * 10.0
            result = result + ((fractionPart.get(digitIndex) - 48) as Double) / divisor
            digitIndex = digitIndex + 1
        }
        if isInf(result) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "number: overflow"))
        }
        if negative { result = 0.0 - result }
        return Ok(result)
    }

    private String assemble(Bool negative, String integerPart, String fractionPart) {
        String padded = integerPart
        while padded.length() < self._minIntegerDigits { padded = "0" + padded }
        String grouped = padded
        if self._grouping {
            grouped = ""
            Int index = 0
            while index < padded.length() {
                Int remaining = padded.length() - index
                if index > 0 && (remaining % 3) == 0 {
                    grouped = grouped + self._groupingSeparator
                }
                grouped = grouped + padded.substring(index, 1)
                index = index + 1
            }
        }
        String body = grouped
        if fractionPart != "" {
            body = body + self._decimalSeparator + fractionPart
        }
        String result = self._prefix + body + self._suffix
        if negative { result = "-" + result }
        return result
    }

    private static Bool affixInvalid(String text) {
        Int index = 0
        while index < text.length() {
            Int code = text.get(index)
            if (code >= 48 && code <= 57) || code == 46 || code == 44 ||
                code == 37 || code == 8240 || code == 164 || code == 43 || code == 45 {
                return true
            }
            index = index + 1
        }
        return false
    }

    private static Bool validGrouping(String pattern) {
        return NumberFormat.validGroupedDigits(pattern, ",")
    }

    private static Bool validGroupedDigits(String text, String separator) {
        Int segmentLength = 0
        Int segments = 0
        Int index = 0
        while index < text.length() {
            if text.substring(index, separator.length()) == separator {
                if segments == 0 {
                    if segmentLength < 1 || segmentLength > 3 { return false }
                } else if segmentLength != 3 {
                    return false
                }
                segments = segments + 1
                segmentLength = 0
                index = index + separator.length()
            } else {
                segmentLength = segmentLength + 1
                index = index + 1
            }
        }
        if segments < 1 { return false }
        return segmentLength == 3
    }

    private static Bool digitsOnly(String text) {
        if text == "" { return false }
        Int index = 0
        while index < text.length() {
            Int code = text.get(index)
            if code < 48 || code > 57 { return false }
            index = index + 1
        }
        return true
    }

    private static String groupingSeparatorFor(Locale locale) {
        String language = locale.language()
        String country = locale.country()
        if language == "de" && country == "CH" { return "'" }
        if language == "de" || language == "es" || language == "pt" { return "." }
        if language == "fr" || language == "ru" { return " " }
        return ","
    }

    private static String decimalSeparatorFor(Locale locale) {
        String language = locale.language()
        String country = locale.country()
        if language == "de" && country == "CH" { return "." }
        if language == "de" || language == "es" || language == "fr" ||
            language == "pt" || language == "ru" { return "," }
        return "."
    }
}

static String terminalPad(String text, Int count) {
    String result = ""
    Int index = 0
    while index < count {
        result = result + text
        index = index + 1
    }
    return result
}
