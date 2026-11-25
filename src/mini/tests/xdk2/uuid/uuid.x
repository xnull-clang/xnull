package app.uuid
import xdk.uuid
import xdk.errors
import xdk.bytes
import xdk.time

static Int main() {
    Uuid v4 = Uuid.v4().value()
    String text = v4.toString()
    print("v4=" + uuidVersionName(v4.version()) + "," + str(v4.variant()) + "," +
        str(text.length()) + "," + str(v4.isNil()))

    Uuid parsed = Uuid.parse(text).value()
    Uuid upper = Uuid.parse(text.toUpper()).value()
    Uuid compact = Uuid.parse(text.substring(0, 8) + text.substring(9, 4) + text.substring(14, 4) +
        text.substring(19, 4) + text.substring(24, 12)).value()
    print("parse=" + str(parsed.equals(v4)) + "," + str(upper.equals(v4)) + "," +
        str(compact.equals(v4)))

    Bool badLength = Uuid.parse("xyz").isErr()
    Bool badHyphen = Uuid.parse("00000000-0000-4000-8000-00000000000z").isErr()
    Bool badVersion = Uuid.parse("00000000-0000-1000-8000-000000000000").isErr()
    print("parse-bad=" + str(badLength) + "," + str(badHyphen) + "," + str(badVersion))

    Uuid nil = Uuid.fromBytes(Bytes.alloc(16))
    print("nil=" + str(nil.isNil()) + "," + str(nil.toString()))

    Uuid v7 = Uuid.v7().value()
    Long? timestamp = v7.timestamp()
    Long now = nowWall()
    Bool timestampOk = timestamp != null && (now - (timestamp as Long)) < 5000 &&
        (now - (timestamp as Long)) > -5000
    print("v7=" + uuidVersionName(v7.version()) + "," + str(timestampOk))

    Uuid nilCopy = Uuid.fromBytes(Bytes.alloc(16))
    Bytes changedCopy = nilCopy.bytes()
    changedCopy.set(0, 1)
    print("copy=" + str(nilCopy.isNil()) + "," + str(changedCopy.get(0) == 1))

    Ulid ulid = Ulid.generate(true).value()
    String ulidText = ulid.toString()
    Ulid ulidParsed = Ulid.parse(ulidText).value()
    print("ulid=" + str(ulidText.length()) + "," + str(ulidParsed.equals(ulid)) + "," +
        str(ulid.randomness().length()))

    Long ulidNow = nowWall()
    Bool ulidTimeOk = (ulidNow - ulid.timestamp()) < 5000 && (ulidNow - ulid.timestamp()) > -5000
    print("ulid-time=" + str(ulidTimeOk))

    Ulid ulidOne = Ulid.generate(true).value()
    Ulid ulidTwo = Ulid.generate(true).value()
    Ulid ulidThree = Ulid.generate(true).value()
    Bool ordered = ulidOne.compare(ulidTwo) < 0 && ulidTwo.compare(ulidThree) < 0
    print("ulid-order=" + str(ordered))

    Bool ulidBadLength = Ulid.parse("ABC").isErr()
    Bool ulidBadChar = Ulid.parse("01ARZ3NDEKTSV4RRFFQ69G5FAI").isErr()
    Bool ulidBadLead = Ulid.parse("81ARZ3NDEKTSV4RRFFQ69G5FAV").isErr()
    print("ulid-bad=" + str(ulidBadLength) + "," + str(ulidBadChar) + "," + str(ulidBadLead))
    return 0
}
