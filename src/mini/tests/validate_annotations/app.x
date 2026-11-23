package app.validate
import xdk.validate

@Validate
class SignupForm {
    @Min(2) @Max(8)
    String name
    @Min(18) @Max(120)
    Int age
    @Min(1000) @Max(9000000000)
    Long score
    @Min(0) @Max(10)
    Double rating
    @Pattern("^[a-z0-9_]+$")
    String handle
    String? nickname
    @Min(1)
    Int? optionalAge
}

@Validate
class EmailForm {
    @Min(3)
    @Pattern("^.+$")
    @Email
    String email
    @Email
    String? backupEmail
}
