package app.genericlambda
import xdk.errors

class Box<T> {
    Result<T, Error> load(T key, Result<T, Error>(T) loader) {
        return loader(key)
    }
}

static Result<T, Error> ident<T>(T value) {
    return Ok(value)
}

static Int main() {
    Box<Int> box = new Box<Int>()
    Result<Int, Error>(Int) increment = (Int value) -> {
        return Ok(value + 1)
    }
    Result<Int, Error> loaded = box.load(1, increment)
    print("loaded=" + str(loaded.isOk()) + "," + str(loaded.value()))

    Result<Int, Error>(Int) failing = (Int value) -> {
        return Err(new BasicError(ErrorKind.Io, "loader"))
    }
    Result<Int, Error> failed = box.load(1, failing)
    print("failed=" + str(failed.isErr()) + "," + errorKindName(failed.error().kind()))

    Result<Int, Error>(Int) genericCall = (Int value) -> {
        return ident<Int>(value)
    }
    Result<Int, Error> called = box.load(7, genericCall)
    print("generic-call=" + str(called.value()))

    Box<Int> inner = new Box<Int>()
    Box<Box<Int>> outer = new Box<Box<Int>>()
    Result<Box<Int>, Error>(Box<Int>) nestedLoader = (Box<Int> value) -> {
        return Ok(inner)
    }
    Result<Box<Int>, Error> nested = outer.load(inner, nestedLoader)
    print("nested=" + str(nested.isOk()) + "," + str(nested.value() == inner))
    return 0
}
