package app.ext
import xdk.annotations

@Retention(Source)
@Target(Constructor)
@annotation Widen {
    final Double factor = 0.0
    final String[] tags = []
}

class Widget {
    Double value
    Widget(Double value) {
        self.value = value
    }
    @Widen(1.5, ["a", "b"])
    Widget(Double value, Bool flag) {
        self.value = value
    }
}
