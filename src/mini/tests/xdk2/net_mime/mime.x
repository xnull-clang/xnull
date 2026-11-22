import xdk.net.mime
static Int main() {
    Result<MediaType, Error> parsed = MediaType.parse("Text/HTML; charset=UTF-8")
    print(parsed.isOk())
    MediaType media = parsed.value()
    print(media.type())
    print(media.subtype())
    print(media.charset())
    print(media.isText())
    print(media.isJson())
    print(media.text())
    MediaType json = MimeTypes.json()
    print(json.type())
    print(json.subtype())
    print(json.isJson())
    MediaType? png = MimeTypes.fromExtension("png")
    MediaType actualPng = png as MediaType
    print(actualPng.type())
    print(MimeTypes.fromExtension("unknown") == null)
    print(MimeTypes.extensionFor(json))
    print(MimeTypes.charsetFor(json))
    MediaType withParam = media.withParameter("level", "1")
    print(withParam.parameter("level"))
    Result<MediaType, Error> bad = MediaType.parse("invalid")
    print(bad.isOk())
    return 0
}
