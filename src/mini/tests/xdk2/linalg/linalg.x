import xdk.linalg
import xdk.tensor
import xdk.errors
static Int main() {
    List<Double> vv = [1.0, 2.0, 3.0]
    List<Double> ww = [2.0, 2.0, 2.0]
    Vector v = new Vector(vv)
    print(v.length())
    print(v.dot(new Vector(ww)))
    print(v.norm())
    List<Double> mm = [1.0, 2.0, 3.0, 4.0]
    Matrix m = new Matrix(2, 2, mm)
    print(m.rowCount())
    print(m.columnCount())
    print(m.get(1, 1))
    print(Linalg.determinant(m))
    List<Double> rhs = [5.0, 11.0]
    Result<Vector, Error> solved = Linalg.solve(m, new Vector(rhs))
    print(solved.isOk())
    print(solved.value().get(0))
    Result<Matrix, Error> inv = Linalg.inverse(m)
    print(inv.isOk())
    Matrix id = Linalg.identity(2)
    print(id.get(0, 0))
    Result<LuDecomposition, Error> lu = LuDecomposition.factor(m)
    print(lu.isOk())
    print(lu.value().isSingular())
    print(lu.value().determinant())
    Result<QrDecomposition, Error> qr = QrDecomposition.factor(m)
    print(qr.isOk())
    print(qr.value().isFullRank())
    Result<Svd, Error> svd = Svd.decompose(m)
    print(svd.isOk())
    print(svd.value().rank())
    List<Double> sym = [2.0, 1.0, 1.0, 2.0]
    Result<EigenDecomposition, Error> eigen = EigenDecomposition.ofSymmetric(new Matrix(2, 2, sym))
    print(eigen.isOk())
    print(eigen.value().values().get(0))
    Matrix bridgeSource = new Matrix(2, 2, mm)
    Matrix bridgeCopy = bridgeSource.copy()
    Tensor bridgeTensor = Linalg.tensorFromMatrix(bridgeSource)
    print(bridgeTensor.rank())
    print(bridgeTensor.tensorShape().dim(0))
    print(bridgeTensor.tensorShape().dim(1))
    print(bridgeTensor.tensorDType() == TensorDType.Float64)
    Result<Matrix, Error> bridgeBack = Linalg.matrixFromTensor(bridgeTensor)
    print(bridgeBack.isOk())
    print(bridgeBack.value().rowCount())
    print(bridgeBack.value().columnCount())
    print(bridgeBack.value().get(0, 0))
    print(bridgeBack.value().get(1, 1))
    print(bridgeSource.equals(bridgeCopy))
    print(bridgeTensor.toDoubles().get(2))

    List<Int> rank0Dims = []
    List<Double> oneValue = [7.0]
    Tensor rank0 = TensorOps.fromDoubles(TensorDType.Float64, new TensorShape(rank0Dims), oneValue)
    print(Linalg.matrixFromTensor(rank0).isErr())
    List<Int> rank1Dims = [2]
    List<Double> twoValues = [1.0, 2.0]
    Tensor rank1 = TensorOps.fromDoubles(TensorDType.Float64, new TensorShape(rank1Dims), twoValues)
    print(Linalg.matrixFromTensor(rank1).isErr())
    List<Int> rank3Dims = [1, 2, 2]
    List<Double> fourValues = [1.0, 2.0, 3.0, 4.0]
    Tensor rank3 = TensorOps.fromDoubles(TensorDType.Float64, new TensorShape(rank3Dims), fourValues)
    print(Linalg.matrixFromTensor(rank3).isErr())

    List<Int> bridgeDims = [2, 2]
    Tensor boolTensor = TensorOps.zeros(TensorDType.Bool, new TensorShape(bridgeDims))
    Result<Matrix, Error> boolResult = Linalg.matrixFromTensor(boolTensor)
    print(boolResult.isErr())
    print(boolResult.error().kind() == ErrorKind.Unsupported)

    Tensor int32Tensor = TensorOps.fromDoubles(TensorDType.Int32, new TensorShape(bridgeDims), fourValues)
    Result<Matrix, Error> int32Result = Linalg.matrixFromTensor(int32Tensor)
    print(int32Result.isOk())
    print(int32Result.value().get(1, 0))
    Tensor int64Tensor = TensorOps.fromDoubles(TensorDType.Int64, new TensorShape(bridgeDims), fourValues)
    Result<Matrix, Error> int64Result = Linalg.matrixFromTensor(int64Tensor)
    print(int64Result.isOk())
    print(int64Result.value().get(0, 1))

    print(Linalg.matrixFromTensor(null).isErr())
    return 0
}
