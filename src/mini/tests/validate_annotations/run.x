package app.validate
import xdk.validate
import xdk.codec
import generated.ValidateGenerated

static JsonValue j(String text) {
    return Json.parse(text).value()
}

static String first(ValidationResult result) {
    if result.isValid() { return "ok" }
    ValidationError error = result.errors().get(0)
    return error.path() + ":" + error.code()
}

static String validBody() {
    return "{\"name\":\"Ada\",\"age\":30,\"score\":1000,\"rating\":5.0,\"handle\":\"a_b1\"}"
}

static Int main() {
    print("valid=" + str(SignupFormValidate(j(validBody())).isValid()))

    print("name-short=" + first(SignupFormValidate(j("{\"name\":\"A\",\"age\":30,\"score\":1000,\"rating\":5.0,\"handle\":\"a_b1\"}"))))
    print("name-long=" + first(SignupFormValidate(j("{\"name\":\"abcdefghi\",\"age\":30,\"score\":1000,\"rating\":5.0,\"handle\":\"a_b1\"}"))))
    print("age-low=" + first(SignupFormValidate(j("{\"name\":\"Ada\",\"age\":17,\"score\":1000,\"rating\":5.0,\"handle\":\"a_b1\"}"))))
    print("age-high=" + first(SignupFormValidate(j("{\"name\":\"Ada\",\"age\":121,\"score\":1000,\"rating\":5.0,\"handle\":\"a_b1\"}"))))
    print("score-low=" + first(SignupFormValidate(j("{\"name\":\"Ada\",\"age\":30,\"score\":999,\"rating\":5.0,\"handle\":\"a_b1\"}"))))
    print("score-high=" + first(SignupFormValidate(j("{\"name\":\"Ada\",\"age\":30,\"score\":9000000001,\"rating\":5.0,\"handle\":\"a_b1\"}"))))
    print("rating-low=" + first(SignupFormValidate(j("{\"name\":\"Ada\",\"age\":30,\"score\":1000,\"rating\":-1.0,\"handle\":\"a_b1\"}"))))
    print("rating-high=" + first(SignupFormValidate(j("{\"name\":\"Ada\",\"age\":30,\"score\":1000,\"rating\":11.0,\"handle\":\"a_b1\"}"))))
    print("pattern=" + first(SignupFormValidate(j("{\"name\":\"Ada\",\"age\":30,\"score\":1000,\"rating\":5.0,\"handle\":\"BAD!\"}"))))

    print("missing-required=" + first(SignupFormValidate(j("{\"age\":30,\"score\":1000,\"rating\":5.0,\"handle\":\"a_b1\"}"))))
    print("wrong-type=" + first(SignupFormValidate(j("{\"name\":\"Ada\",\"age\":\"30\",\"score\":1000,\"rating\":5.0,\"handle\":\"a_b1\"}"))))
    print("nullable-missing=" + str(SignupFormValidate(j(validBody())).isValid()))
    print("nullable-null=" + str(SignupFormValidate(j("{\"name\":\"Ada\",\"age\":30,\"score\":1000,\"rating\":5.0,\"handle\":\"a_b1\",\"nickname\":null}")).isValid()))
    print("nullable-type=" + first(SignupFormValidate(j("{\"name\":\"Ada\",\"age\":30,\"score\":1000,\"rating\":5.0,\"handle\":\"a_b1\",\"nickname\":1}"))))
    print("unsupported-skip=" + str(SignupFormValidate(j("{\"name\":\"Ada\",\"age\":30,\"score\":1000,\"rating\":5.0,\"handle\":\"a_b1\",\"optionalAge\":\"x\"}")).isValid()))

    ValidationResult multi = SignupFormValidate(j("{\"name\":\"A\",\"age\":10,\"score\":1000,\"rating\":5.0,\"handle\":\"BAD!\"}"))
    print("multi-count=" + str(multi.errorCount()))
    print("multi-paths=" + multi.errors().get(0).path() + "," + multi.errors().get(1).path() + "," + multi.errors().get(2).path())

    ValidationResult result = SignupFormValidate(j("{\"name\":\"A\",\"age\":10,\"score\":1000,\"rating\":5.0,\"handle\":\"BAD!\"}"))
    print("toresult=" + str(result.toResult().isErr()))
    print("fields=" + str(SignupFormSchema().fields().length()))
    print("describe=" + SignupFormSchema().describe())
    return 0
}
