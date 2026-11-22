package app
import xdk.annotations

@Retention(Runtime)
@Target(Deinit)
@annotation Cleanup {
    final String name = ""
}

class Resource {
    String state = "live"

    @Cleanup("resource")
    deinit() {
        self.state = "dead"
        print("cleanup")
    }
}

static Int main() {
    Resource r = new Resource()
    AnnotationRegistry reg = xdkAnnotationRegistry()
    AnnotationSet set = reg.ofTarget(AnnotationTarget.Deinit, "app.Resource#deinit()")
    print(set.has("app.Cleanup"))
    print(set.length())
    print(r.state)
    print("main")
    return 0
}
