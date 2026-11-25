#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.xml
import xdk.xml
import xdk.bytes
import xdk.errors

static Int main(String[] args) {
    String name = args.get(0)
    XmlOptions options = new XmlOptions()
    XmlElement element = new XmlElement("a")
    if name == "nameNull" {
        XmlElement value = new XmlElement(null)
    } else if name == "nameEmpty" {
        XmlElement value = new XmlElement("")
    } else if name == "nameInvalid" {
        XmlElement value = new XmlElement("1bad")
    } else if name == "attributeNull" {
        String? value = element.attributeOrNull(null)
    } else if name == "setAttributeNull" {
        element.setAttribute(null, "v")
    } else if name == "setAttributeInvalid" {
        element.setAttribute("1bad", "v")
    } else if name == "setAttributeValueNull" {
        element.setAttribute("k", null)
    } else if name == "removeAttributeNull" {
        Bool removed = element.removeAttribute(null)
    } else if name == "addChildNull" {
        element.addChild(null)
    } else if name == "addChildSelf" {
        element.addChild(element)
    } else if name == "addChildText" {
        element.setText("x")
        element.addChild(new XmlElement("b"))
    } else if name == "setTextChildren" {
        element.addChild(new XmlElement("b"))
        element.setText("x")
    } else if name == "parseNull" {
        Result<XmlElement, Error> value = Xml.parse(null)
    } else if name == "parseOptionsNull" {
        Result<XmlElement, Error> value = Xml.parseWithOptions("<a/>", null)
    } else if name == "parseTextNull" {
        Result<XmlElement, Error> value = Xml.parseWithOptions(null, options)
    } else if name == "parseBytesNull" {
        Result<XmlElement, Error> value = Xml.parseBytes(null)
    } else if name == "stringifyNull" {
        Result<String, Error> value = Xml.stringify(null)
    } else if name == "isXmlNull" {
        Bool value = Xml.isXml(null)
    } else if name == "depthZero" {
        options.maxDepth(0)
    } else if name == "bytesZero" {
        options.maxBytes(0 as Long)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "xml panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "xml panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic nameNull "XmlElement: empty name"
check_panic nameEmpty "XmlElement: empty name"
check_panic nameInvalid "XmlElement: invalid name"
check_panic attributeNull "XmlElement.attributeOrNull: null name"
check_panic setAttributeNull "XmlElement.setAttribute: empty name"
check_panic setAttributeInvalid "XmlElement.setAttribute: invalid name"
check_panic setAttributeValueNull "XmlElement.setAttribute: null value"
check_panic removeAttributeNull "XmlElement.removeAttribute: null name"
check_panic addChildNull "XmlElement.addChild: null child"
check_panic addChildSelf "XmlElement.addChild: self reference"
check_panic addChildText "XmlElement.addChild: element already has text"
check_panic setTextChildren "XmlElement.setText: element already has children"
check_panic parseNull "Xml.parse: null argument"
check_panic parseOptionsNull "Xml.parse: null argument"
check_panic parseTextNull "Xml.parse: null argument"
check_panic parseBytesNull "Xml.parseBytes: null argument"
check_panic stringifyNull "Xml.stringify: null argument"
check_panic isXmlNull "Xml.isXml: null data"
check_panic depthZero "XmlOptions.maxDepth: must be positive"
check_panic bytesZero "XmlOptions.maxBytes: must be positive"
echo "xml_panic: PASS"
