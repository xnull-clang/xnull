package app.csv
import generated.CsvGenerated

class UserCsv {
    Long id
    String name
    Int age
    Double score
    Bool active
    String note
    UserCsv(Long id, String name, Int age, Double score, Bool active, String note) {
        self.id = id
        self.name = name
        self.age = age
        self.score = score
        self.active = active
        self.note = note
    }
}

static String escaped(String text) {
    return text.replace("\n", "\\n")
}

static Int main() {
    UserCsv value = new UserCsv(7, "a,b\"c\nline", 30, 1.5, true, "x,y")
    print("header=" + escaped(UserCsvCsvHeader()))
    String csv = UserCsvToCsv(value)
    print("csv=" + escaped(csv))
    Result<UserCsv, Error> roundtrip = UserCsvFromCsv(csv)
    print("roundtrip=" + str(roundtrip.isOk()))
    UserCsv parsed = roundtrip.value()
    print("values=" + str(parsed.id) + "," + escaped(parsed.name) + "," + str(parsed.age) + "," + str(parsed.score) + "," + str(parsed.active) + "," + escaped(parsed.note))

    String reordered = "name,user_id,age,score,active,note\nAda,8,31,2.5,false,z\n"
    UserCsv reorderedValue = UserCsvFromCsv(reordered).value()
    print("reordered=" + str(reorderedValue.id) + "," + reorderedValue.name)

    String missing = "name,age,score,active,note\nAda,1,1.0,true,x\n"
    Result<UserCsv, Error> missingResult = UserCsvFromCsv(missing)
    print("missing=" + str(missingResult.isErr()) + "," + missingResult.error().describe())

    String badNumber = "user_id,name,age,score,active,note\n1,Ada,oops,1.0,true,x\n"
    print("bad-number=" + UserCsvFromCsv(badNumber).error().describe())
    String badBool = "user_id,name,age,score,active,note\n1,Ada,1,1.0,yes,x\n"
    print("bad-bool=" + UserCsvFromCsv(badBool).error().describe())
    String emptyNumber = "user_id,name,age,score,active,note\n1,Ada,,1.0,true,x\n"
    print("empty-number=" + UserCsvFromCsv(emptyNumber).error().describe())

    String multi = "user_id,name,age,score,active,note\n1,A,10,1.0,true,a\n2,B,20,2.0,false,b\n"
    Result<List<UserCsv>, Error> rows = UserCsvFromCsvRows(multi)
    print("rows=" + str(rows.value().length()) + "," + rows.value().get(1).name)
    UserCsv first = UserCsvFromCsv(multi).value()
    print("first=" + str(first.id) + "," + first.name)

    String unknown = "extra,user_id,name,age,score,active,note\nignored,9,Z,40,4.0,true,q\n"
    UserCsv unknownValue = UserCsvFromCsv(unknown).value()
    print("unknown=" + str(unknownValue.id) + "," + unknownValue.name)

    String crlf = "user_id,name,age,score,active,note\r\n3,C,50,5.0,false,r\r\n"
    UserCsv crlfValue = UserCsvFromCsv(crlf).value()
    print("crlf=" + str(crlfValue.id) + "," + crlfValue.name)

    print("missing-header=" + UserCsvFromCsv("").error().describe())
    print("header-only=" + UserCsvFromCsv("user_id,name,age,score,active,note\n").error().describe())
    return 0
}
