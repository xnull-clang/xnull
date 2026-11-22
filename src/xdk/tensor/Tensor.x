// xdk.tensor — CPU dense tensors with explicit dtype/shape and checked views.
// Tier: L6；依赖：xdk.math、xdk.errors、xdk.bytes；稳定性：preview。
package xdk.tensor
import xdk.math
import xdk.errors
import xdk.bytes

enum TensorDType {
    Float32,
    Float64,
    Int32,
    Int64,
    Bool,
}

Int tensorDTypeByteWidth(TensorDType tensorDType) {
    if tensorDType == null { return 0 }
    if tensorDType == TensorDType.Float32 { return 4 }
    if tensorDType == TensorDType.Float64 { return 8 }
    if tensorDType == TensorDType.Int32 { return 4 }
    if tensorDType == TensorDType.Int64 { return 8 }
    if tensorDType == TensorDType.Bool { return 1 }
    return 0
}

String tensorDTypeName(TensorDType tensorDType) {
    if tensorDType == null { return "unknown" }
    if tensorDType == TensorDType.Float32 { return "float32" }
    if tensorDType == TensorDType.Float64 { return "float64" }
    if tensorDType == TensorDType.Int32 { return "int32" }
    if tensorDType == TensorDType.Int64 { return "int64" }
    if tensorDType == TensorDType.Bool { return "bool" }
    return "other"
}

TensorDType? tensorDTypeFromName(String name) {
    if name == null { return null }
    String normalized = name.trim().toLower()
    if normalized == "float32" { return TensorDType.Float32 }
    if normalized == "float64" { return TensorDType.Float64 }
    if normalized == "int32" { return TensorDType.Int32 }
    if normalized == "int64" { return TensorDType.Int64 }
    if normalized == "bool" { return TensorDType.Bool }
    return null
}

Bool tensorDTypeIsFloatingPoint(TensorDType tensorDType) {
    if tensorDType == null { return false }
    return tensorDType == TensorDType.Float32 || tensorDType == TensorDType.Float64
}

Bool tensorDTypeIsInteger(TensorDType tensorDType) {
    if tensorDType == null { return false }
    return tensorDType == TensorDType.Int32 || tensorDType == TensorDType.Int64
}

Bool tensorDTypeIsBoolean(TensorDType tensorDType) {
    if tensorDType == null { return false }
    return tensorDType == TensorDType.Bool
}

class TensorShape {
    final List<Int> _dimensions

    TensorShape(List<Int> dimensions) {
        if dimensions == null { throw "TensorShape: null dimensions" }
        List<Int> copy = []
        Long count = 1
        Int index = 0
        while index < dimensions.length() {
            Int dim = dimensions.get(index)
            if dim < 0 { throw "TensorShape: negative dimension" }
            copy.push(dim)
            if dim == 0 {
                count = 0
            } else if count > 0 {
                if count > maxLongValue() / (dim as Long) {
                    throw "TensorShape: element count overflow"
                }
                count = count * (dim as Long)
            }
            index = index + 1
        }
        self._dimensions = copy
    }

    Int rank() { return self._dimensions.length() }
    Bool isScalar() { return self._dimensions.length() == 0 }
    Int dim(Int dimensionIndex) {
        if dimensionIndex < 0 || dimensionIndex >= self._dimensions.length() {
            throw "TensorShape.dim: index out of range"
        }
        return self._dimensions.get(dimensionIndex)
    }
    List<Int> dimensions() { return self._dimensions.copy() }

    Long elementCount() {
        Long count = 1
        Int index = 0
        while index < self._dimensions.length() {
            Int dim = self._dimensions.get(index)
            if dim == 0 { return 0 }
            if count > maxLongValue() / (dim as Long) {
                throw "TensorShape.elementCount: overflow"
            }
            count = count * (dim as Long)
            index = index + 1
        }
        return count
    }

    TensorShape withDim(Int dimensionIndex, Int dimensionSize) {
        if dimensionIndex < 0 || dimensionIndex >= self._dimensions.length() {
            throw "TensorShape.withDim: index out of range"
        }
        if dimensionSize < 0 { throw "TensorShape.withDim: negative size" }
        List<Int> next = self._dimensions.copy()
        next.set(dimensionIndex, dimensionSize)
        return new TensorShape(next)
    }

    List<Long> rowMajorStrides() {
        List<Long> result = []
        Int rankValue = self._dimensions.length()
        if rankValue == 0 { return result }
        Long stride = 1
        Int index = rankValue - 1
        while index >= 0 {
            if self._dimensions.get(index) == 0 {
                Int reset = 0
                while reset < rankValue {
                    result.insert(0, 0)
                    reset = reset + 1
                }
                return result
            }
            result.insert(0, stride)
            stride = stride * (self._dimensions.get(index) as Long)
            index = index - 1
        }
        return result
    }

    Long flatIndex(List<Int> indices) {
        if indices == null { throw "TensorShape.flatIndex: null indices" }
        if indices.length() != self._dimensions.length() {
            throw "TensorShape.flatIndex: rank mismatch"
        }
        List<Long> strides = self.rowMajorStrides()
        Long result = 0
        Int index = 0
        while index < indices.length() {
            Int value = indices.get(index)
            if value < 0 || value >= self._dimensions.get(index) {
                throw "TensorShape.flatIndex: index out of range"
            }
            result = result + (value as Long) * strides.get(index)
            index = index + 1
        }
        return result
    }

    Bool equals(TensorShape other) {
        if other == null { return false }
        if other.rank() != self.rank() { return false }
        Int index = 0
        while index < self._dimensions.length() {
            if self._dimensions.get(index) != other.dim(index) { return false }
            index = index + 1
        }
        return true
    }

    String describe() {
        String result = "["
        Int index = 0
        while index < self._dimensions.length() {
            if index > 0 { result = result + "," }
            result = result + str(self._dimensions.get(index))
            index = index + 1
        }
        return result + "]"
    }

    TensorShape copy() { return new TensorShape(self._dimensions) }
}

Bytes tensorZeroData(Int byteCount) {
    if byteCount < 0 { throw "tensorZeroData: negative size" }
    Bytes result = Bytes.fromString("")
    Int index = 0
    while index < byteCount {
        result.push(0)
        index = index + 1
    }
    return result
}

Long tensorBits(TensorDType dtype, Double value) {
    if dtype == TensorDType.Float64 { return f64BitsRaw(value) }
    if dtype == TensorDType.Int64 { return value as Long }
    if dtype == TensorDType.Int32 { return (value as Int) as Long }
    return 0
}

Void tensorWriteElement(Bytes data, Int byteOffset, TensorDType dtype, Double value) {
    if dtype == TensorDType.Bool {
        Bool flag = value != 0.0
        if !flag { data.set(byteOffset, 0) } else { data.set(byteOffset, 1) }
        return
    }
    Int width = tensorDTypeByteWidth(dtype)
    Long bits = tensorBits(dtype, value)
    if dtype == TensorDType.Float32 { bits = f32BitsRaw(value) }
    Int index = 0
    while index < width {
        Long shifted = bits >> (index * 8)
        data.set(byteOffset + index, (shifted & 255) as Int)
        index = index + 1
    }
}

Double tensorReadElement(Bytes data, Int byteOffset, TensorDType dtype) {
    if dtype == TensorDType.Bool { return (data.get(byteOffset) as Double) }
    if dtype == TensorDType.Float32 { return f32FromBitsRaw(readIntLE(data, byteOffset) as Long) }
    if dtype == TensorDType.Float64 { return f64FromBitsRaw(readLongLE(data, byteOffset)) }
    if dtype == TensorDType.Int32 { return (readIntLE(data, byteOffset) as Double) }
    return (readLongLE(data, byteOffset) as Double)
}

class Tensor {
    final TensorDType _dtype
    final TensorShape _shape
    final Bytes _data

    Tensor(TensorDType tensorDType, TensorShape tensorShape, Bytes data) {
        if tensorDType == null || tensorShape == null || data == null {
            throw "Tensor: null argument"
        }
        Long expected = tensorShape.elementCount() * (tensorDTypeByteWidth(tensorDType) as Long)
        if expected > 2147483647L {
            throw "Tensor: byte length exceeds Int limit"
        }
        if data.length() != (expected as Int) {
            throw "Tensor: data length mismatch"
        }
        if tensorDType == TensorDType.Bool {
            Int index = 0
            while index < data.length() {
                Int value = data.get(index)
                if value != 0 && value != 1 { throw "Tensor: invalid Bool byte" }
                index = index + 1
            }
        }
        Bytes copy = Bytes.fromString("")
        Int index = 0
        while index < data.length() {
            copy.push(data.get(index))
            index = index + 1
        }
        self._dtype = tensorDType
        self._shape = tensorShape
        self._data = copy
    }

    TensorDType tensorDType() { return self._dtype }
    TensorShape tensorShape() { return self._shape }
    Int rank() { return self._shape.rank() }
    Long elementCount() { return self._shape.elementCount() }
    Long byteLength() { return self._data.length() as Long }
    Bool isScalar() { return self._shape.isScalar() }

    Double at(List<Int> indices) { return self.atFlat(self._shape.flatIndex(indices)) }

    Double atFlat(Long elementIndex) {
        if elementIndex < 0 || elementIndex >= self.elementCount() {
            throw "Tensor.atFlat: index out of range"
        }
        Int width = tensorDTypeByteWidth(self._dtype)
        return tensorReadElement(self._data, (elementIndex as Int) * width, self._dtype)
    }

    Long atLong(List<Int> indices) {
        if !tensorDTypeIsInteger(self._dtype) && self._dtype != TensorDType.Bool {
            throw "Tensor.atLong: dtype is not integer"
        }
        return self.atFlat(indexList(indices)) as Long
    }

    Long atFlatLong(Long elementIndex) {
        if !tensorDTypeIsInteger(self._dtype) && self._dtype != TensorDType.Bool {
            throw "Tensor.atFlatLong: dtype is not integer"
        }
        return self.atFlat(elementIndex) as Long
    }

    Long indexList(List<Int> indices) { return self._shape.flatIndex(indices) }

    Bool atBool(List<Int> indices) {
        if self._dtype != TensorDType.Bool { throw "Tensor.atBool: dtype is not Bool" }
        return self.at(indices) != 0.0
    }

    Tensor withValue(List<Int> indices, Double value) {
        Long target = self._shape.flatIndex(indices)
        List<Double> values = self.toDoubles()
        values.set(target as Int, value)
        return TensorOps.fromDoubles(self._dtype, self._shape, values)
    }

    List<Double> toDoubles() {
        List<Double> result = []
        Long index = 0
        while index < self.elementCount() {
            result.push(self.atFlat(index))
            index = index + 1
        }
        return result
    }

    Tensor copy() { return new Tensor(self._dtype, self._shape, self._data) }

    Bool equals(Tensor other) {
        if other == null { return false }
        if other._dtype != self._dtype || !other._shape.equals(self._shape) { return false }
        Long index = 0
        while index < self.elementCount() {
            Double left = self.atFlat(index)
            Double right = other.atFlat(index)
            if isNaN(left) || isNaN(right) { return false }
            if left != right { return false }
            index = index + 1
        }
        return true
    }

    String describe() {
        return tensorDTypeName(self._dtype) + " " + self._shape.describe() + " elements=" + str(self.elementCount())
    }
}

class TensorView {
    final Tensor _base
    final TensorShape _shape
    final List<Long> _strides
    final Long _offset

    TensorView(Tensor baseTensor, TensorShape tensorShape, List<Long> strides, Long elementOffset) {
        self._base = baseTensor
        self._shape = tensorShape
        self._strides = strides
        self._offset = elementOffset
    }

    static TensorView of(Tensor baseTensor, TensorShape tensorShape, List<Long> strides, Long elementOffset) {
        if baseTensor == null || tensorShape == null || strides == null {
            throw "TensorView.of: null argument"
        }
        if tensorShape.rank() != strides.length() {
            throw "TensorView.of: rank mismatch"
        }
        if elementOffset < 0 { throw "TensorView.of: negative offset" }
        List<Long> copy = strides.copy()
        Long maximum = elementOffset
        Int index = 0
        while index < copy.length() {
            Long stride = copy.get(index)
            if stride < 0 { throw "TensorView.of: negative stride" }
            Int dim = tensorShape.dim(index)
            if stride == 0 && dim > 1 && tensorShape.elementCount() > 0 {
                throw "TensorView.of: stride 0 on non-empty dimension"
            }
            if dim > 1 && stride > 0 {
                Long steps = (dim - 1) as Long
                if steps > (maxLongValue() - maximum) / stride {
                    throw "TensorView.of: maximum element index overflow"
                }
                maximum = maximum + steps * stride
            }
            index = index + 1
        }
        if tensorShape.elementCount() > 0 && maximum >= baseTensor.elementCount() {
            throw "TensorView.of: view exceeds base tensor"
        }
        return new TensorView(baseTensor, tensorShape, copy, elementOffset)
    }

    Tensor baseTensor() { return self._base }
    TensorShape tensorShape() { return self._shape }
    Int rank() { return self._shape.rank() }
    Long elementCount() { return self._shape.elementCount() }
    Long stride(Int dimensionIndex) {
        if dimensionIndex < 0 || dimensionIndex >= self._strides.length() {
            throw "TensorView.stride: index out of range"
        }
        return self._strides.get(dimensionIndex)
    }
    Long offset() { return self._offset }

    Long flatAt(List<Int> indices) {
        if indices == null || indices.length() != self._shape.rank() {
            throw "TensorView.at: rank mismatch"
        }
        Long index = self._offset
        Int dim = 0
        while dim < indices.length() {
            Int value = indices.get(dim)
            if value < 0 || value >= self._shape.dim(dim) {
                throw "TensorView.at: index out of range"
            }
            index = index + (value as Long) * self._strides.get(dim)
            dim = dim + 1
        }
        return index
    }

    Double at(List<Int> indices) { return self._base.atFlat(self.flatAt(indices)) }
    Long atLong(List<Int> indices) { return self._base.atFlatLong(self.flatAt(indices)) }

    Bool isContiguous() {
        List<Long> expected = self._shape.rowMajorStrides()
        if expected.length() != self._strides.length() { return false }
        Int index = 0
        while index < expected.length() {
            if expected.get(index) != self._strides.get(index) { return false }
            index = index + 1
        }
        return true
    }

    TensorView transpose() {
        List<Int> dims = []
        List<Long> strides = []
        Int index = self._shape.rank() - 1
        while index >= 0 {
            dims.push(self._shape.dim(index))
            strides.push(self._strides.get(index))
            index = index - 1
        }
        return TensorView.of(self._base, new TensorShape(dims), strides, self._offset)
    }

    Tensor toTensor() {
        List<Double> values = []
        Long count = self.elementCount()
        Long index = 0
        while index < count {
            List<Int> indices = []
            Long remaining = index
            Int dim = self._shape.rank() - 1
            while dim >= 0 {
                Int size = self._shape.dim(dim)
                if size == 0 { indices.insert(0, 0) } else {
                    indices.insert(0, (remaining % (size as Long)) as Int)
                    remaining = remaining / (size as Long)
                }
                dim = dim - 1
            }
            values.push(self.at(indices))
            index = index + 1
        }
        return TensorOps.fromDoubles(self._base.tensorDType(), self._shape, values)
    }

    String describe() { return "TensorView " + self._shape.describe() + " offset=" + str(self._offset) }
}

class TensorOps {
    static Tensor zeros(TensorDType tensorDType, TensorShape tensorShape) {
        if tensorDType == null || tensorShape == null { throw "TensorOps.zeros: null argument" }
        Int byteCount = (tensorShape.elementCount() * (tensorDTypeByteWidth(tensorDType) as Long)) as Int
        return new Tensor(tensorDType, tensorShape, tensorZeroData(byteCount))
    }

    static Tensor ones(TensorDType tensorDType, TensorShape tensorShape) {
        return fill(tensorDType, tensorShape, 1.0)
    }

    static Tensor fill(TensorDType tensorDType, TensorShape tensorShape, Double value) {
        if tensorDType == null || tensorShape == null { throw "TensorOps.fill: null argument" }
        List<Double> values = []
        Long count = tensorShape.elementCount()
        Long index = 0
        while index < count {
            values.push(value)
            index = index + 1
        }
        return fromDoubles(tensorDType, tensorShape, values)
    }

    static Tensor fromDoubles(TensorDType tensorDType, TensorShape tensorShape, List<Double> values) {
        if tensorDType == null || tensorShape == null || values == null {
            throw "TensorOps.fromDoubles: null argument"
        }
        if (values.length() as Long) != tensorShape.elementCount() {
            throw "TensorOps.fromDoubles: length mismatch"
        }
        Int width = tensorDTypeByteWidth(tensorDType)
        Int byteCount = (tensorShape.elementCount() * (width as Long)) as Int
        Bytes data = tensorZeroData(byteCount)
        Int index = 0
        while index < values.length() {
            tensorWriteElement(data, index * width, tensorDType, values.get(index))
            index = index + 1
        }
        return new Tensor(tensorDType, tensorShape, data)
    }

    static Tensor reshape(Tensor tensor, TensorShape tensorShape) {
        if tensor == null || tensorShape == null { throw "TensorOps.reshape: null argument" }
        if tensor.elementCount() != tensorShape.elementCount() {
            throw "TensorOps.reshape: element count mismatch"
        }
        return fromDoubles(tensor.tensorDType(), tensorShape, tensor.toDoubles())
    }

    static Tensor transpose(Tensor tensor) {
        if tensor == null { throw "TensorOps.transpose: null tensor" }
        if tensor.rank() < 2 { return tensor.copy() }
        List<Int> dims = tensor.tensorShape().dimensions()
        List<Int> reversedDims = []
        Int index = dims.length() - 1
        while index >= 0 {
            reversedDims.push(dims.get(index))
            index = index - 1
        }
        TensorShape shape = new TensorShape(reversedDims)
        List<Double> values = []
        Long count = shape.elementCount()
        Long flat = 0
        while flat < count {
            Int remaining = flat as Int
            List<Int> oldIndices = []
            Int dim = reversedDims.length() - 1
            while dim >= 0 {
                Int size = reversedDims.get(dim)
                Int coordinate = 0
                if size > 0 { coordinate = remaining % size; remaining = remaining / size }
                oldIndices.insert(0, coordinate)
                dim = dim - 1
            }
            List<Int> source = []
            index = oldIndices.length() - 1
            while index >= 0 {
                source.push(oldIndices.get(index))
                index = index - 1
            }
            values.push(tensor.at(source))
            flat = flat + 1
        }
        return fromDoubles(tensor.tensorDType(), shape, values)
    }

    static Tensor add(Tensor left, Tensor right) {
        return elementwise(left, right, true)
    }

    static Tensor mul(Tensor left, Tensor right) {
        return elementwise(left, right, false)
    }

    static Tensor elementwise(Tensor left, Tensor right, Bool adding) {
        if left == null || right == null { throw "TensorOps: null tensor" }
        if left.tensorDType() != right.tensorDType() || !left.tensorShape().equals(right.tensorShape()) {
            throw "TensorOps: dtype/shape mismatch"
        }
        if left.tensorDType() == TensorDType.Bool { throw "TensorOps: Bool arithmetic" }
        List<Double> leftValues = left.toDoubles()
        List<Double> rightValues = right.toDoubles()
        List<Double> result = []
        Int index = 0
        while index < leftValues.length() {
            if adding { result.push(leftValues.get(index) + rightValues.get(index)) }
            else { result.push(leftValues.get(index) * rightValues.get(index)) }
            index = index + 1
        }
        return fromDoubles(left.tensorDType(), left.tensorShape(), result)
    }

    static Tensor matmul(Tensor left, Tensor right) {
        if left == null || right == null { throw "TensorOps.matmul: null tensor" }
        if left.rank() != 2 || right.rank() != 2 { throw "TensorOps.matmul: rank must be 2" }
        if left.tensorDType() != right.tensorDType() { throw "TensorOps.matmul: dtype mismatch" }
        if left.tensorDType() == TensorDType.Bool { throw "TensorOps.matmul: Bool" }
        Int m = left.tensorShape().dim(0)
        Int k = left.tensorShape().dim(1)
        Int k2 = right.tensorShape().dim(0)
        Int n = right.tensorShape().dim(1)
        if k != k2 { throw "TensorOps.matmul: inner dimension mismatch" }
        List<Double> result = []
        Int row = 0
        while row < m {
            Int column = 0
            while column < n {
                Double total = 0.0
                Int inner = 0
                while inner < k {
                    List<Int> leftIndex = []
                    leftIndex.push(row)
                    leftIndex.push(inner)
                    List<Int> rightIndex = []
                    rightIndex.push(inner)
                    rightIndex.push(column)
                    total = total + left.at(leftIndex) * right.at(rightIndex)
                    inner = inner + 1
                }
                result.push(total)
                column = column + 1
            }
            row = row + 1
        }
        return fromDoubles(left.tensorDType(), new TensorShape([m, n]), result)
    }

    static Tensor sum(Tensor tensor) {
        if tensor == null { throw "TensorOps.sum: null tensor" }
        if tensor.tensorDType() == TensorDType.Bool { throw "TensorOps.sum: Bool" }
        List<Double> values = tensor.toDoubles()
        Double total = 0.0
        Int index = 0
        while index < values.length() {
            total = total + values.get(index)
            index = index + 1
        }
        List<Double> result = []
        result.push(total)
        return fromDoubles(tensor.tensorDType(), new TensorShape([]), result)
    }
}
