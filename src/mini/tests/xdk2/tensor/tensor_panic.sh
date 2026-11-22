#!/bin/sh
# Tensor contract panics: stride 0, Long overflow, view bound, no broadcast, Bool math, shift bound.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

check_panic() {
    name=$1
    marker=$2
    file=$3
    "$XNULL" --bootstrap --engine=mini run "$TMP/$file" >"$TMP/$file.out" 2>"$TMP/$file.err" && {
        echo "tensor panic: $name did not fail" >&2
        exit 1
    }
    grep -q "$marker" "$TMP/$file.err" || {
        echo "tensor panic: $name missing marker '$marker'" >&2
        cat "$TMP/$file.err" >&2
        exit 1
    }
}

cat > "$TMP/stride.x" <<'X'
import xdk.tensor
static Int main() {
    List<Int> dims = [2, 2]
    List<Double> values = [1.0, 2.0, 3.0, 4.0]
    Tensor base = TensorOps.fromDoubles(TensorDType.Float64, new TensorShape(dims), values)
    List<Long> strides = [0, 1]
    TensorView.of(base, new TensorShape(dims), strides, 0)
    return 0
}
X
check_panic "stride0" "stride 0 on non-empty dimension" stride.x

cat > "$TMP/overflow.x" <<'X'
import xdk.tensor
import xdk.math
static Int main() {
    List<Int> dims = [2, 2]
    List<Double> values = [1.0, 2.0, 3.0, 4.0]
    Tensor base = TensorOps.fromDoubles(TensorDType.Float64, new TensorShape(dims), values)
    List<Long> strides = [maxLongValue(), 1]
    TensorView.of(base, new TensorShape(dims), strides, 0)
    return 0
}
X
check_panic "overflow" "maximum element index overflow" overflow.x

cat > "$TMP/bound.x" <<'X'
import xdk.tensor
static Int main() {
    List<Int> dims = [2, 2]
    List<Double> values = [1.0, 2.0, 3.0, 4.0]
    Tensor base = TensorOps.fromDoubles(TensorDType.Float64, new TensorShape(dims), values)
    List<Long> strides = [1, 1]
    TensorView.of(base, new TensorShape(dims), strides, 3)
    return 0
}
X
check_panic "view bound" "view exceeds base tensor" bound.x

cat > "$TMP/shape.x" <<'X'
import xdk.tensor
static Int main() {
    List<Int> a = [2]
    List<Int> b = [1, 2]
    List<Double> va = [1.0, 2.0]
    List<Double> vb = [1.0, 2.0]
    Tensor left = TensorOps.fromDoubles(TensorDType.Float64, new TensorShape(a), va)
    Tensor right = TensorOps.fromDoubles(TensorDType.Float64, new TensorShape(b), vb)
    TensorOps.add(left, right)
    return 0
}
X
check_panic "no broadcast" "dtype/shape mismatch" shape.x

cat > "$TMP/bool.x" <<'X'
import xdk.tensor
static Int main() {
    List<Int> dims = [2]
    List<Double> values = [1.0, 0.0]
    Tensor left = TensorOps.fromDoubles(TensorDType.Bool, new TensorShape(dims), values)
    TensorOps.add(left, left)
    return 0
}
X
check_panic "bool arithmetic" "Bool arithmetic" bool.x

cat > "$TMP/shift.x" <<'X'
static Int main() {
    Long value = 1
    Long count = 64
    print(value << count)
    return 0
}
X
check_panic "shift bound" "shift count out of range" shift.x

echo "tensor panic: PASS (6 case(s))"
