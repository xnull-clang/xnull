// xdk.linalg — dense real double-precision linear algebra.
// Tier: L6；依赖：xdk.math、xdk.errors、xdk.tensor；稳定性：preview。
package xdk.linalg
import xdk.math
import xdk.errors
import xdk.tensor

Error linalgError(ErrorKind kind, String message) { return new BasicError(kind, message) }

class Vector {
    final List<Double> _values

    Vector(List<Double> values) {
        if values == null { throw "Vector: null values" }
        self._values = values.copy()
    }

    Int length() { return self._values.length() }
    Double get(Int index) {
        if index < 0 || index >= self._values.length() { throw "Vector.get: index out of range" }
        return self._values.get(index)
    }
    List<Double> toList() { return self._values.copy() }
    Vector copy() { return new Vector(self._values) }

    Double dot(Vector other) {
        if other == null || other.length() != self.length() { throw "Vector.dot: length mismatch" }
        Double total = 0.0
        Int index = 0
        while index < self._values.length() {
            total = total + self._values.get(index) * other.get(index)
            index = index + 1
        }
        return total
    }

    Double norm() {
        Double scale = 0.0
        Double sum = 0.0
        Int index = 0
        while index < self._values.length() {
            Double value = abs(self._values.get(index))
            if value > scale {
                if scale != 0.0 { sum = sum * (scale / value) * (scale / value) }
                scale = value
            }
            if value != 0.0 { sum = sum + (value / scale) * (value / scale) }
            index = index + 1
        }
        return scale * sqrt(sum)
    }

    Vector add(Vector other) {
        if other == null || other.length() != self.length() { throw "Vector.add: length mismatch" }
        List<Double> result = []
        Int index = 0
        while index < self._values.length() {
            result.push(self._values.get(index) + other.get(index))
            index = index + 1
        }
        return new Vector(result)
    }

    Vector scale(Double factor) {
        List<Double> result = []
        Int index = 0
        while index < self._values.length() {
            result.push(self._values.get(index) * factor)
            index = index + 1
        }
        return new Vector(result)
    }

    Bool equals(Vector other) {
        if other == null || other.length() != self.length() { return false }
        Int index = 0
        while index < self._values.length() {
            Double left = self._values.get(index)
            Double right = other.get(index)
            if isNaN(left) || isNaN(right) { return false }
            if left != right { return false }
            index = index + 1
        }
        return true
    }

    String describe() { return "Vector(" + str(self.length()) + ")" }
}

class Matrix {
    final Int _rowCount
    final Int _columnCount
    final List<Double> _values

    Matrix(Int rowCount, Int columnCount, List<Double> values) {
        if rowCount < 0 || columnCount < 0 || values == null { throw "Matrix: invalid argument" }
        if rowCount * columnCount != values.length() { throw "Matrix: length mismatch" }
        self._rowCount = rowCount
        self._columnCount = columnCount
        self._values = values.copy()
    }

    Int rowCount() { return self._rowCount }
    Int columnCount() { return self._columnCount }
    Bool isSquare() { return self._rowCount == self._columnCount }
    Double get(Int rowIndex, Int columnIndex) {
        if rowIndex < 0 || rowIndex >= self._rowCount || columnIndex < 0 || columnIndex >= self._columnCount {
            throw "Matrix.get: index out of range"
        }
        return self._values.get(rowIndex * self._columnCount + columnIndex)
    }
    Matrix withValue(Int rowIndex, Int columnIndex, Double value) {
        self.get(rowIndex, columnIndex)
        List<Double> next = self._values.copy()
        next.set(rowIndex * self._columnCount + columnIndex, value)
        return new Matrix(self._rowCount, self._columnCount, next)
    }
    List<Double> toList() { return self._values.copy() }
    Matrix copy() { return new Matrix(self._rowCount, self._columnCount, self._values) }

    Matrix multiply(Matrix other) {
        if other == null || self._columnCount != other.rowCount() { throw "Matrix.multiply: dimension mismatch" }
        List<Double> result = []
        Int row = 0
        while row < self._rowCount {
            Int column = 0
            while column < other.columnCount() {
                Double total = 0.0
                Int inner = 0
                while inner < self._columnCount {
                    total = total + self.get(row, inner) * other.get(inner, column)
                    inner = inner + 1
                }
                result.push(total)
                column = column + 1
            }
            row = row + 1
        }
        return new Matrix(self._rowCount, other.columnCount(), result)
    }

    Vector multiplyVector(Vector vector) {
        if vector == null || vector.length() != self._columnCount { throw "Matrix.multiplyVector: dimension mismatch" }
        List<Double> result = []
        Int row = 0
        while row < self._rowCount {
            Double total = 0.0
            Int column = 0
            while column < self._columnCount {
                total = total + self.get(row, column) * vector.get(column)
                column = column + 1
            }
            result.push(total)
            row = row + 1
        }
        return new Vector(result)
    }

    Matrix transpose() {
        List<Double> result = []
        Int column = 0
        while column < self._columnCount {
            Int row = 0
            while row < self._rowCount {
                result.push(self.get(row, column))
                row = row + 1
            }
            column = column + 1
        }
        return new Matrix(self._columnCount, self._rowCount, result)
    }

    Vector row(Int rowIndex) {
        if rowIndex < 0 || rowIndex >= self._rowCount { throw "Matrix.row: index out of range" }
        List<Double> result = []
        Int column = 0
        while column < self._columnCount {
            result.push(self.get(rowIndex, column))
            column = column + 1
        }
        return new Vector(result)
    }

    Vector column(Int columnIndex) {
        if columnIndex < 0 || columnIndex >= self._columnCount { throw "Matrix.column: index out of range" }
        List<Double> result = []
        Int row = 0
        while row < self._rowCount {
            result.push(self.get(row, columnIndex))
            row = row + 1
        }
        return new Vector(result)
    }

    Bool equals(Matrix other) {
        if other == null || other.rowCount() != self._rowCount || other.columnCount() != self._columnCount {
            return false
        }
        Int index = 0
        while index < self._values.length() {
            Double left = self._values.get(index)
            Double right = other.toList().get(index)
            if isNaN(left) || isNaN(right) { return false }
            if left != right { return false }
            index = index + 1
        }
        return true
    }

    String describe() { return str(self._rowCount) + "x" + str(self._columnCount) }
}

class LuDecomposition {
    final Matrix _lu
    final List<Int> _pivot
    final Int _sign
    final Bool _singular
    final Int _size

    LuDecomposition(Matrix lu, List<Int> pivot, Int sign, Bool singular) {
        self._lu = lu
        self._pivot = pivot
        self._sign = sign
        self._singular = singular
        self._size = lu.rowCount()
    }

    static Result<LuDecomposition, Error> factor(Matrix matrix) {
        if matrix == null { throw "LuDecomposition.factor: null matrix" }
        if !matrix.isSquare() || matrix.rowCount() < 1 {
            return Err(linalgError(ErrorKind.InvalidArgument, "LU requires a non-empty square matrix"))
        }
        Int n = matrix.rowCount()
        List<Double> values = matrix.toList()
        Int index = 0
        while index < values.length() {
            if !isFinite(values.get(index)) {
                return Err(linalgError(ErrorKind.InvalidArgument, "LU requires finite values"))
            }
            index = index + 1
        }
        List<Int> pivot = []
        index = 0
        while index < n { pivot.push(index); index = index + 1 }
        Int sign = 1
        Bool singular = false
        Int column = 0
        while column < n {
            Int pivotRow = column
            Double best = abs(values.get(column * n + column))
            Int row = column + 1
            while row < n {
                Double candidate = abs(values.get(row * n + column))
                if candidate > best { best = candidate; pivotRow = row }
                row = row + 1
            }
            if best <= 0.000000000001 { singular = true }
            if pivotRow != column {
                Int c = 0
                while c < n {
                    Double temp = values.get(column * n + c)
                    values.set(column * n + c, values.get(pivotRow * n + c))
                    values.set(pivotRow * n + c, temp)
                    c = c + 1
                }
                Int tempPivot = pivot.get(column)
                pivot.set(column, pivot.get(pivotRow))
                pivot.set(pivotRow, tempPivot)
                sign = -sign
            }
            Double diagonal = values.get(column * n + column)
            if diagonal != 0.0 {
                row = column + 1
                while row < n {
                    Double factorValue = values.get(row * n + column) / diagonal
                    values.set(row * n + column, factorValue)
                    Int c = column + 1
                    while c < n {
                        values.set(row * n + c, values.get(row * n + c) - factorValue * values.get(column * n + c))
                        c = c + 1
                    }
                    row = row + 1
                }
            }
            column = column + 1
        }
        return Ok(new LuDecomposition(new Matrix(n, n, values), pivot, sign, singular))
    }

    Bool isSingular() { return self._singular }
    Int size() { return self._size }

    Result<Vector, Error> solve(Vector rightHandSide) {
        if rightHandSide == null || rightHandSide.length() != self._size {
            throw "LuDecomposition.solve: length mismatch"
        }
        if self._singular {
            return Err(linalgError(ErrorKind.InvalidArgument, "LU solve: singular matrix"))
        }
        List<Double> b = []
        Int index = 0
        while index < self._size {
            b.push(rightHandSide.get(self._pivot.get(index)))
            index = index + 1
        }
        index = 0
        while index < self._size {
            Int column = 0
            while column < index {
                b.set(index, b.get(index) - self._lu.get(index, column) * b.get(column))
                column = column + 1
            }
            index = index + 1
        }
        index = self._size - 1
        while index >= 0 {
            Int column = index + 1
            while column < self._size {
                b.set(index, b.get(index) - self._lu.get(index, column) * b.get(column))
                column = column + 1
            }
            Double diagonal = self._lu.get(index, index)
            if diagonal == 0.0 {
                return Err(linalgError(ErrorKind.InvalidArgument, "LU solve: zero pivot"))
            }
            b.set(index, b.get(index) / diagonal)
            index = index - 1
        }
        return Ok(new Vector(b))
    }

    Double determinant() {
        if self._singular { return 0.0 }
        Double result = self._sign as Double
        Int index = 0
        while index < self._size {
            result = result * self._lu.get(index, index)
            index = index + 1
        }
        return result
    }
}

class QrDecomposition {
    final Matrix _q
    final Matrix _r
    final Bool _fullRank
    final Int _rows
    final Int _columns

    QrDecomposition(Matrix q, Matrix r, Bool fullRank, Int rows, Int columns) {
        self._q = q
        self._r = r
        self._fullRank = fullRank
        self._rows = rows
        self._columns = columns
    }

    static Result<QrDecomposition, Error> factor(Matrix matrix) {
        if matrix == null { throw "QrDecomposition.factor: null matrix" }
        if matrix.rowCount() < 1 || matrix.columnCount() < 1 {
            return Err(linalgError(ErrorKind.InvalidArgument, "QR requires non-empty matrix"))
        }
        if matrix.rowCount() < matrix.columnCount() {
            return Err(linalgError(ErrorKind.Unsupported, "QR requires rows >= columns"))
        }
        Int m = matrix.rowCount()
        Int n = matrix.columnCount()
        List<Double> qValues = []
        Int fill = 0
        while fill < m * n { qValues.push(0.0); fill = fill + 1 }
        List<Double> rValues = []
        fill = 0
        while fill < n * n { rValues.push(0.0); fill = fill + 1 }
        Int column = 0
        Bool fullRank = true
        while column < n {
            List<Double> vector = []
            Int row = 0
            while row < m { vector.push(matrix.get(row, column)); row = row + 1 }
            Int previous = 0
            while previous < column {
                Double dotValue = 0.0
                row = 0
                while row < m {
                    dotValue = dotValue + qValues.get(row * n + previous) * vector.get(row)
                    row = row + 1
                }
                rValues.set(previous * n + column, dotValue)
                row = 0
                while row < m {
                    vector.set(row, vector.get(row) - dotValue * qValues.get(row * n + previous))
                    row = row + 1
                }
                previous = previous + 1
            }
            Double normValue = 0.0
            row = 0
            while row < m { normValue = normValue + vector.get(row) * vector.get(row); row = row + 1 }
            normValue = sqrt(normValue)
            if normValue <= 0.000000000001 { fullRank = false }
            rValues.set(column * n + column, normValue)
            row = 0
            if normValue > 0.0 {
                while row < m {
                    qValues.set(row * n + column, vector.get(row) / normValue)
                    row = row + 1
                }
            }
            column = column + 1
        }
        return Ok(new QrDecomposition(new Matrix(m, n, qValues), new Matrix(n, n, rValues), fullRank, m, n))
    }

    Matrix q() { return self._q }
    Matrix r() { return self._r }
    Bool isFullRank() { return self._fullRank }
    Int rowCount() { return self._rows }
    Int columnCount() { return self._columns }

    Result<Vector, Error> solveLeastSquares(Vector rightHandSide) {
        if rightHandSide == null || rightHandSide.length() != self._rows {
            throw "QrDecomposition.solveLeastSquares: length mismatch"
        }
        if !self._fullRank {
            return Err(linalgError(ErrorKind.InvalidArgument, "QR solve: rank deficient"))
        }
        List<Double> y = []
        Int column = 0
        while column < self._columns {
            Double total = 0.0
            Int row = 0
            while row < self._rows {
                total = total + self._q.get(row, column) * rightHandSide.get(row)
                row = row + 1
            }
            y.push(total)
            column = column + 1
        }
        Int index = self._columns - 1
        while index >= 0 {
            Int next = index + 1
            while next < self._columns {
                y.set(index, y.get(index) - self._r.get(index, next) * y.get(next))
                next = next + 1
            }
            Double diagonal = self._r.get(index, index)
            if diagonal == 0.0 { return Err(linalgError(ErrorKind.InvalidArgument, "QR solve: zero diagonal")) }
            y.set(index, y.get(index) / diagonal)
            index = index - 1
        }
        return Ok(new Vector(y))
    }
}

class EigenDecomposition {
    final Vector _values
    final Matrix _eigenvectors

    EigenDecomposition(Vector values, Matrix eigenvectors) {
        self._values = values
        self._eigenvectors = eigenvectors
    }

    static Result<EigenDecomposition, Error> ofSymmetric(Matrix matrix) {
        if matrix == null { throw "EigenDecomposition.ofSymmetric: null matrix" }
        if !matrix.isSquare() || matrix.rowCount() < 1 {
            return Err(linalgError(ErrorKind.InvalidArgument, "eigen requires non-empty square matrix"))
        }
        Int n = matrix.rowCount()
        Int index = 0
        while index < matrix.toList().length() {
            if !isFinite(matrix.toList().get(index)) {
                return Err(linalgError(ErrorKind.InvalidArgument, "eigen requires finite values"))
            }
            index = index + 1
        }
        index = 0
        while index < n {
            Int column = index + 1
            while column < n {
                Double tolerance = 0.000000001 * (1.0 + abs(matrix.get(index, column)))
                if abs(matrix.get(index, column) - matrix.get(column, index)) > tolerance {
                    return Err(linalgError(ErrorKind.Unsupported, "eigen requires symmetric matrix"))
                }
                column = column + 1
            }
            index = index + 1
        }
        List<Double> a = matrix.toList()
        List<Double> v = []
        index = 0
        while index < n * n {
            v.push(0.0)
            index = index + 1
        }
        index = 0
        while index < n { v.set(index * n + index, 1.0); index = index + 1 }
        Int iteration = 0
        while iteration < 100 {
            Int p = 0
            Int q = 1
            Double largest = 0.0
            Int row = 0
            while row < n {
                Int column = row + 1
                while column < n {
                    Double value = abs(a.get(row * n + column))
                    if value > largest { largest = value; p = row; q = column }
                    column = column + 1
                }
                row = row + 1
            }
            if largest < 0.000000000001 { break }
            Double angle = 0.5 * atan2(2.0 * a.get(p * n + q), a.get(q * n + q) - a.get(p * n + p))
            Double cosine = cos(angle)
            Double sine = sin(angle)
            Int k = 0
            while k < n {
                Double apk = a.get(p * n + k)
                Double aqk = a.get(q * n + k)
                a.set(p * n + k, cosine * apk - sine * aqk)
                a.set(q * n + k, sine * apk + cosine * aqk)
                k = k + 1
            }
            k = 0
            while k < n {
                Double akp = a.get(k * n + p)
                Double akq = a.get(k * n + q)
                a.set(k * n + p, cosine * akp - sine * akq)
                a.set(k * n + q, sine * akp + cosine * akq)
                k = k + 1
            }
            k = 0
            while k < n {
                Double vkp = v.get(k * n + p)
                Double vkq = v.get(k * n + q)
                v.set(k * n + p, cosine * vkp - sine * vkq)
                v.set(k * n + q, sine * vkp + cosine * vkq)
                k = k + 1
            }
            iteration = iteration + 1
        }
        List<Double> eigenvalues = []
        index = 0
        while index < n { eigenvalues.push(a.get(index * n + index)); index = index + 1 }
        Int first = 0
        while first < n {
            Int best = first
            Int candidate = first + 1
            while candidate < n {
                if eigenvalues.get(candidate) > eigenvalues.get(best) { best = candidate }
                candidate = candidate + 1
            }
            if best != first {
                Double temp = eigenvalues.get(first)
                eigenvalues.set(first, eigenvalues.get(best))
                eigenvalues.set(best, temp)
                Int rowIndex = 0
                while rowIndex < n {
                    Double vectorTemp = v.get(rowIndex * n + first)
                    v.set(rowIndex * n + first, v.get(rowIndex * n + best))
                    v.set(rowIndex * n + best, vectorTemp)
                    rowIndex = rowIndex + 1
                }
            }
            first = first + 1
        }
        return Ok(new EigenDecomposition(new Vector(eigenvalues), new Matrix(n, n, v)))
    }

    Vector values() { return self._values }
    Matrix eigenvectors() { return self._eigenvectors }
}

class Svd {
    final Matrix _u
    final Vector _singularValues
    final Matrix _vt
    final Int _rank

    Svd(Matrix u, Vector singularValues, Matrix vt, Int rankValue) {
        self._u = u
        self._singularValues = singularValues
        self._vt = vt
        self._rank = rankValue
    }

    static Result<Svd, Error> decompose(Matrix matrix) {
        if matrix == null { throw "Svd.decompose: null matrix" }
        if matrix.rowCount() < 1 || matrix.columnCount() < 1 {
            return Err(linalgError(ErrorKind.InvalidArgument, "SVD requires non-empty matrix"))
        }
        Int index = 0
        while index < matrix.toList().length() {
            if !isFinite(matrix.toList().get(index)) {
                return Err(linalgError(ErrorKind.InvalidArgument, "SVD requires finite values"))
            }
            index = index + 1
        }
        Matrix ata = matrix.transpose().multiply(matrix)
        Result<EigenDecomposition, Error> eigenResult = EigenDecomposition.ofSymmetric(ata)
        if !eigenResult.isOk() { return Err(eigenResult.error()) }
        EigenDecomposition eigen = eigenResult.value()
        Int n = matrix.columnCount()
        Int m = matrix.rowCount()
        Int k = m
        if n < k { k = n }
        List<Double> singular = []
        index = 0
        while index < k {
            Double value = eigen.values().get(index)
            if value < 0.0 { value = 0.0 }
            singular.push(sqrt(value))
            index = index + 1
        }
        Matrix v = eigen.eigenvectors()
        List<Double> uValues = []
        Int fill = 0
        while fill < m * k { uValues.push(0.0); fill = fill + 1 }
        Int column = 0
        while column < k {
            Double sigma = singular.get(column)
            if sigma > 0.000000000001 {
                Int row = 0
                while row < m {
                    Double total = 0.0
                    Int inner = 0
                    while inner < n {
                        total = total + matrix.get(row, inner) * v.get(inner, column)
                        inner = inner + 1
                    }
                    uValues.set(row * k + column, total / sigma)
                    row = row + 1
                }
            }
            column = column + 1
        }
        List<Double> vtValues = []
        Int row = 0
        while row < k {
            Int col = 0
            while col < n {
                vtValues.push(v.get(col, row))
                col = col + 1
            }
            row = row + 1
        }
        Int rankValue = 0
        Double tolerance = 0.000000001 * (singular.get(0) + 1.0)
        index = 0
        while index < singular.length() {
            if singular.get(index) > tolerance { rankValue = rankValue + 1 }
            index = index + 1
        }
        return Ok(new Svd(new Matrix(m, k, uValues), new Vector(singular), new Matrix(k, n, vtValues), rankValue))
    }

    Matrix u() { return self._u }
    Vector singularValues() { return self._singularValues }
    Matrix vt() { return self._vt }
    Int rank() { return self._rank }

    Double condition() {
        if self._singularValues.length() == 0 { return Inf() }
        Double smallest = self._singularValues.get(self._singularValues.length() - 1)
        if smallest == 0.0 { return Inf() }
        return self._singularValues.get(0) / smallest
    }
}

class Linalg {
    static Double dot(Vector left, Vector right) {
        if left == null || right == null { throw "Linalg.dot: null vector" }
        return left.dot(right)
    }

    static Vector cross(Vector left, Vector right) {
        if left == null || right == null || left.length() != 3 || right.length() != 3 {
            throw "Linalg.cross: requires 3D vectors"
        }
        List<Double> result = []
        result.push(left.get(1) * right.get(2) - left.get(2) * right.get(1))
        result.push(left.get(2) * right.get(0) - left.get(0) * right.get(2))
        result.push(left.get(0) * right.get(1) - left.get(1) * right.get(0))
        return new Vector(result)
    }

    static Double norm(Vector vector) {
        if vector == null { throw "Linalg.norm: null vector" }
        return vector.norm()
    }

    static Result<Vector, Error> solve(Matrix matrix, Vector rightHandSide) {
        if matrix == null || rightHandSide == null { throw "Linalg.solve: null argument" }
        if !matrix.isSquare() { throw "Linalg.solve: matrix must be square" }
        Result<LuDecomposition, Error> factored = LuDecomposition.factor(matrix)
        if !factored.isOk() { return Err(factored.error()) }
        return factored.value().solve(rightHandSide)
    }

    static Result<Matrix, Error> inverse(Matrix matrix) {
        if matrix == null { throw "Linalg.inverse: null matrix" }
        if !matrix.isSquare() { throw "Linalg.inverse: matrix must be square" }
        Result<LuDecomposition, Error> factored = LuDecomposition.factor(matrix)
        if !factored.isOk() { return Err(factored.error()) }
        LuDecomposition lu = factored.value()
        if lu.isSingular() { return Err(linalgError(ErrorKind.InvalidArgument, "inverse: singular matrix")) }
        Int n = matrix.rowCount()
        List<Double> result = []
        Int fill = 0
        while fill < n * n { result.push(0.0); fill = fill + 1 }
        Int column = 0
        while column < n {
            List<Double> basis = []
            Int row = 0
            while row < n {
                if row == column { basis.push(1.0) } else { basis.push(0.0) }
                row = row + 1
            }
            Result<Vector, Error> solved = lu.solve(new Vector(basis))
            if !solved.isOk() { return Err(solved.error()) }
            row = 0
            while row < n {
                result.set(row * n + column, solved.value().get(row))
                row = row + 1
            }
            column = column + 1
        }
        return Ok(new Matrix(n, n, result))
    }

    static Double determinant(Matrix matrix) {
        if matrix == null { throw "Linalg.determinant: null matrix" }
        if !matrix.isSquare() { throw "Linalg.determinant: matrix must be square" }
        if matrix.rowCount() == 0 { return NaN() }
        Result<LuDecomposition, Error> factored = LuDecomposition.factor(matrix)
        if !factored.isOk() { return NaN() }
        return factored.value().determinant()
    }

    static Double trace(Matrix matrix) {
        if matrix == null { throw "Linalg.trace: null matrix" }
        if !matrix.isSquare() { throw "Linalg.trace: matrix must be square" }
        Double total = 0.0
        Int index = 0
        while index < matrix.rowCount() {
            total = total + matrix.get(index, index)
            index = index + 1
        }
        return total
    }

    static Matrix identity(Int size) {
        if size < 0 { throw "Linalg.identity: negative size" }
        List<Double> values = []
        Int row = 0
        while row < size {
            Int column = 0
            while column < size {
                if row == column { values.push(1.0) } else { values.push(0.0) }
                column = column + 1
            }
            row = row + 1
        }
        return new Matrix(size, size, values)
    }


    static Result<Matrix, Error> matrixFromTensor(Tensor tensor) {
        if tensor == null {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Linalg.matrixFromTensor: null tensor"))
        }
        if tensor.rank() != 2 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Linalg.matrixFromTensor: tensor rank must be 2"))
        }
        if tensor.tensorDType() == TensorDType.Bool {
            return Err(new BasicError(ErrorKind.Unsupported,
                "Linalg.matrixFromTensor: bool tensor is not supported"))
        }
        TensorShape tensorShape = tensor.tensorShape()
        return Ok(new Matrix(tensorShape.dim(0), tensorShape.dim(1),
            tensor.toDoubles()))
    }

    static Tensor tensorFromMatrix(Matrix matrix) {
        if matrix == null {
            throw "Linalg.tensorFromMatrix: null matrix"
        }
        List<Int> dimensions = []
        dimensions.push(matrix.rowCount())
        dimensions.push(matrix.columnCount())
        TensorShape tensorShape = new TensorShape(dimensions)
        return TensorOps.fromDoubles(TensorDType.Float64, tensorShape,
            matrix.toList())
    }
}
