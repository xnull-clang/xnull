import xdk.tensor
static Int main() {
    List<Int> dims = [2, 2]
    TensorShape shape = new TensorShape(dims)
    print(shape.rank())
    print(shape.elementCount())
    print(shape.isScalar())
    print(shape.dim(0))
    print(shape.rowMajorStrides().get(1))
    List<Int> index11 = [1, 1]
    print(shape.flatIndex(index11))
    List<Double> values = [1.0, 2.0, 3.0, 4.0]
    Tensor t = TensorOps.fromDoubles(TensorDType.Float64, shape, values)
    print(t.byteLength())
    List<Int> index01 = [0, 1]
    print(t.at(index01))
    print(t.atFlat(3))
    List<Int> index10 = [1, 0]
    Tensor intTensor = TensorOps.fromDoubles(TensorDType.Int64, shape, values)
    print(intTensor.atLong(index10))
    print(intTensor.atFlatLong(2))
    List<Int> index00 = [0, 0]
    Tensor updated = t.withValue(index00, 9.0)
    print(updated.at(index00))
    print(t.at(index00))
    print(t.toDoubles().get(3))
    print(t.equals(updated))
    print(t.describe())
    List<Int> flatDims = [4]
    Tensor reshaped = TensorOps.reshape(t, new TensorShape(flatDims))
    print(reshaped.rank())
    Tensor transposed = TensorOps.transpose(t)
    print(transposed.at(index01))
    Tensor added = TensorOps.add(t, t)
    print(added.at(index11))
    Tensor multiplied = TensorOps.mul(t, t)
    print(multiplied.at(index10))
    Tensor sum = TensorOps.sum(t)
    print(sum.atFlat(0))
    List<Int> leftDims = [1, 2]
    TensorShape leftShape = new TensorShape(leftDims)
    List<Int> rightDims = [2, 1]
    TensorShape rightShape = new TensorShape(rightDims)
    List<Double> leftValues = [1.0, 2.0]
    List<Double> rightValues = [3.0, 4.0]
    Tensor product = TensorOps.matmul(TensorOps.fromDoubles(TensorDType.Float64, leftShape, leftValues), TensorOps.fromDoubles(TensorDType.Float64, rightShape, rightValues))
    print(product.at(index00))
    List<Int> baseDims = [1, 3]
    TensorShape baseShape = new TensorShape(baseDims)
    List<Double> baseValues = [5.0, 6.0, 7.0]
    Tensor base = TensorOps.fromDoubles(TensorDType.Float64, baseShape, baseValues)
    List<Long> zeroStrides = [0, 1]
    TensorView view = TensorView.of(base, baseShape, zeroStrides, 0)
    List<Int> viewIndex = [0, 2]
    print(view.at(viewIndex))
    print(view.isContiguous())
    print(view.transpose().elementCount())
    List<Int> emptyDims = [0, 3]
    TensorShape emptyShape = new TensorShape(emptyDims)
    List<Long> emptyStrides = [0, 0]
    TensorView emptyView = TensorView.of(base, emptyShape, emptyStrides, 0)
    print(emptyView.elementCount())
    print(emptyView.toTensor().elementCount())
    print(tensorDTypeName(TensorDType.Float64))
    print(tensorDTypeByteWidth(TensorDType.Int32))
    print(tensorDTypeIsFloatingPoint(TensorDType.Float64))
    print(tensorDTypeIsInteger(TensorDType.Int64))
    print(tensorDTypeIsBoolean(TensorDType.Bool))
    print(tensorDTypeFromName("float32") != null)
    print(tensorDTypeFromName("unknown") == null)
    print(tensorDTypeFromName("other") == null)
    return 0
}
