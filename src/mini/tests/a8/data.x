@Data
class User {
    String name
    Int age
    User(String name0, Int age0) {
        self.name = name0
        self.age = age0
    }
}
static Int main() {
    User a = new User("ann", 3)
    User b = new User("ann", 3)
    User c = new User("bob", 4)
    print(a.equals(b))
    print(a.equals(c))
    print(a.equals(null))
    print(a.toString())
    User d = a.copy()
    a.name = "changed"
    print(d.name)
    print(a.name)
    return 0
}
