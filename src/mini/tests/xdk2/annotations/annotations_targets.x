@Target(Package)
@annotation PkgTag {
    final String v = ""
}

@Target(Type)
@annotation TypeTag {
    final String v = ""
}

@Target(TypeParameter)
@annotation TpTag {
    final String v = ""
}

@Target(Field)
@annotation FieldTag {
    final String v = ""
}

@Target(Method)
@annotation MethodTag {
    final String v = ""
}

@Target(Constructor)
@annotation CtorTag {
    final String v = ""
}

@Target(Parameter)
@annotation ParamTag {
    final String v = ""
}

@Target(EnumItem)
@annotation ItemTag {
    final String v = ""
}

@Target(Annotation)
@annotation MetaTag {
    final String v = ""
}

@Target(Deinit)
@annotation DeinitTag {
    final String v = ""
}

@Target(TypeUse)
@annotation TypeUseTag {
    final String v = ""
}

@PkgTag("pkg")
package demo

@TypeTag("type")
class Box<@TpTag("t") T> {
    @FieldTag("f") Int value = 0

    @CtorTag("c") Box() {
    }

    @MethodTag("m") Void set(@ParamTag("p") Int v) {
        self.value = v
    }
}

@TypeTag("enum")
enum E {
    @ItemTag("a") A,
    B
}

@MetaTag("meta")
@annotation User {
    final Int n = 0
}

static Int main() {
    print("targets")
    return 0
}
