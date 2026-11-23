package app.csv
import xdk.codec

@Serializable
class UserCsv {
    @CsvName("user_id")
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
