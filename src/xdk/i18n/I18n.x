// xdk.i18n —— Locale/PluralRules/NumberFormat 核心（M21.6）
//
// CLDR 子集：仅列出的语言规则与数字格式；不做脚本/扩展段/全量 CLDR。
// 稳定性：preview。合同见 docs/design/utils/i18n/。
package xdk.i18n
import xdk.errors
import xdk.math
import xdk.text
import xdk.fs

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

// ---------- MessageCatalog ----------
protocol Reader {
    Result<String?, Error> readLine(Context context);
}

class MessageCatalog {
    final Locale _locale
    final Map<String, String> _messages

    MessageCatalog(Locale locale) {
        if locale == null { throw "MessageCatalog: null locale" }
        self._locale = locale
        Map<String, String> messages = [:]
        self._messages = messages
    }

    Locale locale() { return self._locale }
    Int length() { return self._messages.keys().length() }

    Result<Unit, Error> add(String key, String value) {
        if key == null || value == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null catalog entry"))
        }
        if key.trim() == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid message key"))
        }
        if self._messages.has(key) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "duplicate message: " + key))
        }
        self._messages.put(key, value)
        return Ok()
    }

    Result<String, Error> get(String key) {
        if key == null { throw "MessageCatalog.get: null key" }
        if !self._messages.has(key) {
            return Err(new BasicError(ErrorKind.NotFound, "missing message: " + key))
        }
        return Ok(self._messages.getOr(key, ""))
    }

    String getOr(String key, String fallback) {
        if key == null || fallback == null {
            throw "MessageCatalog.getOr: null argument"
        }
        if self._messages.has(key) { return self._messages.getOr(key, "") }
        return fallback
    }

    Bool has(String key) {
        if key == null { return false }
        return self._messages.has(key)
    }

    Bool remove(String key) {
        if key == null { return false }
        return self._messages.remove(key)
    }

    Result<Int, Error> merge(MessageCatalog other, Bool overwrite) {
        if other == null { throw "MessageCatalog.merge: null catalog" }
        if !self._locale.equals(other.locale()) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "catalog locale mismatch"))
        }
        List<String> incoming = other.keys()
        Int index = 0
        while index < incoming.length() {
            String key = incoming.get(index)
            if self._messages.has(key) && !overwrite {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "duplicate message: " + key))
            }
            index = index + 1
        }
        Int imported = 0
        index = 0
        while index < incoming.length() {
            String key = incoming.get(index)
            self._messages.put(key, other.getOr(key, ""))
            imported = imported + 1
            index = index + 1
        }
        return Ok(imported)
    }

    Result<Int, Error> mergeDefault(MessageCatalog other) {
        return self.merge(other, false)
    }

    List<String> keys() { return self._messages.keys() }

    MessageCatalog copy() {
        MessageCatalog result = new MessageCatalog(self._locale)
        List<String> values = self._messages.keys()
        Int index = 0
        while index < values.length() {
            String key = values.get(index)
            result._messages.put(key, self._messages.getOr(key, ""))
            index = index + 1
        }
        return result
    }

    static Result<MessageCatalog, Error> load(Context context, Locale locale, Path path) {
        if context == null || locale == null || path == null {
            throw "MessageCatalog.load: null argument"
        }
        if context.isCancelled() {
            return Err(new BasicError(ErrorKind.Cancelled, "catalog load cancelled"))
        }
        Result<File, Error> opened = openFileRead(path.text())
        if opened.isErr() { return Err(opened.error()) }
        File file = opened.value()
        Result<String, Error> text = file.readText()
        Result<Unit, Error> closed = file.close()
        if text.isErr() { return Err(text.error()) }
        if closed.isErr() { return Err(closed.error()) }
        return MessageCatalog.parse(locale, text.value())
    }

    static Result<MessageCatalog, Error> loadFromReader(Context context, Locale locale,
                                                         Reader reader) {
        if context == null || locale == null || reader == null {
            throw "MessageCatalog.loadFromReader: null argument"
        }
        String text = ""
        while true {
            if context.isCancelled() {
                return Err(new BasicError(ErrorKind.Cancelled, "catalog load cancelled"))
            }
            Result<String?, Error> line = reader.readLine(context)
            if line.isErr() { return Err(line.error()) }
            String? value = line.value()
            if value == null { break }
            if text != "" { text = text + "\n" }
            text = text + (value as String)
        }
        return MessageCatalog.parse(locale, text)
    }

    static Result<MessageCatalog, Error> parse(Locale locale, String text) {
        if locale == null || text == null {
            throw "MessageCatalog.parse: null argument"
        }
        MessageCatalog catalog = new MessageCatalog(locale)
        List<String> rawLines = []
        Int start = 0
        Int index = 0
        while index <= text.length() {
            if index == text.length() || text.get(index) == 10 {
                String line = text.substring(start, index - start)
                if line.length() > 0 && line.get(line.length() - 1) == 13 {
                    line = line.substring(0, line.length() - 1)
                }
                rawLines.push(line)
                start = index + 1
            }
            index = index + 1
        }
        if rawLines.length() > 0 {
            String first = rawLines.get(0)
            if first.length() >= 3 && first.get(0) == 239 && first.get(1) == 187 &&
                first.get(2) == 191 {
                rawLines.set(0, first.substring(3, first.length() - 3))
            } else if first.length() > 0 && first.get(0) == 65279 {
                rawLines.set(0, first.substring(1, first.length() - 1))
            }
        }
        Int lineIndex = 0
        while lineIndex < rawLines.length() {
            String logical = rawLines.get(lineIndex)
            while MessageCatalog.endsWithContinuation(logical) && lineIndex + 1 < rawLines.length() {
                logical = logical.substring(0, logical.length() - 1) + rawLines.get(lineIndex + 1).trim()
                lineIndex = lineIndex + 1
            }
            lineIndex = lineIndex + 1
            String trimmed = logical.trim()
            if trimmed == "" || trimmed.startsWith("#") || trimmed.startsWith("!") {
                continue
            }
            Int separator = MessageCatalog.separatorIndex(trimmed)
            if separator < 0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "line " + str(lineIndex) + ": missing separator"))
            }
            String keyText = trimmed.substring(0, separator).trim()
            String valueText = trimmed.substring(separator + 1, trimmed.length() - separator - 1).trim()
            Result<String, Error> key = MessageCatalog.decode(keyText)
            if key.isErr() {
                return Err(new BasicError(ErrorKind.InvalidArgument, "line " + str(lineIndex) + ": invalid escape"))
            }
            Result<String, Error> value = MessageCatalog.decode(valueText)
            if value.isErr() {
                return Err(new BasicError(ErrorKind.InvalidArgument, "line " + str(lineIndex) + ": invalid escape"))
            }
            if key.value().trim() == "" {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "line " + str(lineIndex) + ": empty key"))
            }
            Result<Unit, Error> added = catalog.add(key.value(), value.value())
            if added.isErr() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "line " + str(lineIndex) + ": duplicate message: " + key.value()))
            }
        }
        return Ok(catalog)
    }

    private static Bool endsWithContinuation(String line) {
        Int count = 0
        Int index = line.length() - 1
        while index >= 0 && line.get(index) == 92 {
            count = count + 1
            index = index - 1
        }
        return count % 2 == 1
    }

    private static Int separatorIndex(String line) {
        Int index = 0
        while index < line.length() {
            Int code = line.get(index)
            if code == 61 || code == 58 { return index }
            index = index + 1
        }
        return -1
    }

    private static Result<String, Error> decode(String text) {
        String result = ""
        Int index = 0
        while index < text.length() {
            Int code = text.get(index)
            if code != 92 {
                result = result + text.substring(index, 1)
                index = index + 1
                continue
            }
            if index + 1 >= text.length() {
                return Err(new BasicError(ErrorKind.InvalidArgument, "trailing escape"))
            }
            Int next = text.get(index + 1)
            if next == 110 { result = result + "\n" }
            else if next == 116 { result = result + "\t" }
            else if next == 114 { result = result + "\r" }
            else if next == 92 { result = result + "\\" }
            else if next == 58 { result = result + ":" }
            else if next == 61 { result = result + "=" }
            else if next == 35 { result = result + "#" }
            else if next == 33 { result = result + "!" }
            else if next == 117 {
                if index + 5 >= text.length() {
                    return Err(new BasicError(ErrorKind.InvalidArgument, "bad unicode escape"))
                }
                Int value = 0
                Int digitIndex = index + 2
                Int digitEnd = index + 6
                while digitIndex < digitEnd {
                    Int digit = MessageCatalog.hexValue(text.get(digitIndex))
                    if digit < 0 {
                        return Err(new BasicError(ErrorKind.InvalidArgument, "bad unicode escape"))
                    }
                    value = value * 16 + digit
                    digitIndex = digitIndex + 1
                }
                result = result + fromCodePoint(value)
                index = index + 6
                continue
            } else {
                return Err(new BasicError(ErrorKind.InvalidArgument, "invalid escape"))
            }
            index = index + 2
        }
        return Ok(result)
    }

    private static Int hexValue(Int code) {
        if code >= 48 && code <= 57 { return code - 48 }
        if code >= 65 && code <= 70 { return code - 55 }
        if code >= 97 && code <= 102 { return code - 87 }
        return -1
    }
}

// ---------- MessageFormatter ----------
class MessageFormatter {
    final Locale _locale
    final PluralRules _pluralRules

    MessageFormatter(Locale locale) {
        if locale == null { throw "MessageFormatter: null locale" }
        self._locale = locale
        self._pluralRules = new PluralRules(locale)
    }

    Locale locale() { return self._locale }

    Result<String, Error> format(String template, Map<String, String> values) {
        if template == null || values == null {
            throw "MessageFormatter.format: null argument"
        }
        String result = ""
        Int index = 0
        while index < template.length() {
            String current = template.substring(index, 1)
            if current == "{" {
                if index + 1 < template.length() && template.substring(index + 1, 1) == "{" {
                    result = result + "{"
                    index = index + 2
                } else {
                    Int close = index + 1
                    while close < template.length() && template.substring(close, 1) != "}" {
                        close = close + 1
                    }
                    if close >= template.length() {
                        return Err(new BasicError(ErrorKind.InvalidArgument, "unclosed placeholder"))
                    }
                    String name = template.substring(index + 1, close - index - 1)
                    if !MessageFormatter.validName(name) {
                        return Err(new BasicError(ErrorKind.InvalidArgument,
                            "invalid placeholder: " + name))
                    }
                    if !values.has(name) {
                        return Err(new BasicError(ErrorKind.InvalidArgument,
                            "missing placeholder: " + name))
                    }
                    result = result + values.getOr(name, "")
                    index = close + 1
                }
            } else if current == "}" {
                if index + 1 < template.length() && template.substring(index + 1, 1) == "}" {
                    result = result + "}"
                    index = index + 2
                } else {
                    return Err(new BasicError(ErrorKind.InvalidArgument, "unmatched '}'"))
                }
            } else {
                result = result + current
                index = index + 1
            }
        }
        return Ok(result)
    }

    Result<String, Error> formatArgs(String template, List<String> arguments) {
        if template == null || arguments == null {
            throw "MessageFormatter.formatArgs: null argument"
        }
        Map<String, String> values = [:]
        Int index = 0
        while index < arguments.length() {
            values.put(str(index), arguments.get(index))
            index = index + 1
        }
        return self.format(template, values)
    }

    Result<String, Error> plural(Double count, Map<String, String> forms) {
        if forms == null { throw "MessageFormatter.plural: null forms" }
        return self._pluralRules.select(count, forms)
    }

    Result<String, Error> select(String value, Map<String, String> cases) {
        if value == null || cases == null {
            throw "MessageFormatter.select: null argument"
        }
        if cases.has(value) { return Ok(cases.getOr(value, "")) }
        if cases.has("other") { return Ok(cases.getOr("other", "")) }
        return Err(new BasicError(ErrorKind.InvalidArgument, "missing select branch: " + value))
    }

    private static Bool validName(String name) {
        if name == "" { return false }
        Int index = 0
        while index < name.length() {
            Int code = name.get(index)
            Bool letter = (code >= 65 && code <= 90) || (code >= 97 && code <= 122)
            Bool digit = code >= 48 && code <= 57
            if !letter && !digit && code != 95 && code != 46 { return false }
            index = index + 1
        }
        return true
    }
}

// ---------- Translator ----------
class Translator {
    final List<MessageCatalog> _catalogs
    final MessageCatalog _active
    final MessageFormatter _formatter

    Translator(MessageCatalog catalog) {
        if catalog == null { throw "Translator: null catalog" }
        MessageCatalog copied = catalog.copy()
        List<MessageCatalog> catalogs = []
        catalogs.push(copied)
        self._catalogs = catalogs
        self._active = copied
        self._formatter = new MessageFormatter(copied.locale())
    }

    private Translator(List<MessageCatalog> catalogs, MessageCatalog active) {
        if catalogs == null || active == null {
            throw "Translator: null argument"
        }
        self._catalogs = catalogs.copy()
        self._active = active
        self._formatter = new MessageFormatter(active.locale())
    }

    Result<String, Error> translate(String key) {
        if key == null { throw "Translator.translate: null key" }
        return self._active.get(key)
    }

    Result<String, Error> translateWithArgs(String key, List<String> arguments) {
        if key == null || arguments == null {
            throw "Translator.translateWithArgs: null argument"
        }
        Result<String, Error> template = self._active.get(key)
        if template.isErr() {
            return Err(new BasicError(ErrorKind.NotFound, "missing message: " + key))
        }
        return self._formatter.formatArgs(template.value(), arguments)
    }

    Result<Translator, Error> withLocale(Locale locale) {
        if locale == null { throw "Translator.withLocale: null locale" }
        Int index = 0
        while index < self._catalogs.length() {
            MessageCatalog candidate = self._catalogs.get(index)
            if candidate.locale().equals(locale) {
                return Ok(new Translator(self._catalogs, candidate))
            }
            index = index + 1
        }
        if locale.country() != "" {
            index = 0
            while index < self._catalogs.length() {
                MessageCatalog candidate = self._catalogs.get(index)
                Locale value = candidate.locale()
                if value.language() == locale.language() &&
                    value.country() == locale.country() && value.variant() == "" {
                    return Ok(new Translator(self._catalogs, candidate))
                }
                index = index + 1
            }
        }
        index = 0
        while index < self._catalogs.length() {
            MessageCatalog candidate = self._catalogs.get(index)
            Locale value = candidate.locale()
            if value.language() == locale.language() &&
                value.country() == "" && value.variant() == "" {
                return Ok(new Translator(self._catalogs, candidate))
            }
            index = index + 1
        }
        index = 0
        while index < self._catalogs.length() {
            MessageCatalog candidate = self._catalogs.get(index)
            if candidate.locale().isRoot() {
                return Ok(new Translator(self._catalogs, candidate))
            }
            index = index + 1
        }
        return Err(new BasicError(ErrorKind.NotFound, "no catalog for locale: " + locale.toString()))
    }

    Translator withCatalog(MessageCatalog catalog) {
        if catalog == null { throw "Translator.withCatalog: null catalog" }
        MessageCatalog copied = catalog.copy()
        List<MessageCatalog> next = []
        Bool replaced = false
        MessageCatalog active = self._active
        Int index = 0
        while index < self._catalogs.length() {
            MessageCatalog current = self._catalogs.get(index)
            if current.locale().equals(copied.locale()) {
                next.push(copied)
                if self._active.locale().equals(copied.locale()) { active = copied }
                replaced = true
            } else {
                next.push(current.copy())
            }
            index = index + 1
        }
        if !replaced { next.push(copied) }
        return new Translator(next, active)
    }

    Locale locale() { return self._active.locale() }
    MessageCatalog catalog() { return self._active.copy() }
}
