import xdk.linalg
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
    return 0
}
