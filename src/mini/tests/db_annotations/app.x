package app.db
import xdk.db
import xdk.sql

@Entity("users")
class UserEntity {
    @Id
    Long id
    @Column("display_name")
    String name
    Int age
    Bool active
    Double score
    UserEntity(Long id, String name, Int age, Bool active, Double score) {
        self.id = id
        self.name = name
        self.age = age
        self.active = active
        self.score = score
    }
}

@Table("audit_log")
class AuditEntity {
    @Id
    Long id
    String action
    AuditEntity(Long id, String action) {
        self.id = id
        self.action = action
    }
}

class UserDao {
    @Transactional
    Result<Long, Error> insertTx(SqlTransaction tx, UserEntity value) {
        Result<SqlResult, Error> inserted = tx.execute(UserEntityInsertStatement(value))
        if inserted.isErr() { return Err(inserted.error()) }
        return Ok(inserted.value().rowsAffected())
    }

    @Transactional
    Result<Long, Error> insertThenFailTx(SqlTransaction tx, UserEntity value) {
        Result<SqlResult, Error> inserted = tx.execute(UserEntityInsertStatement(value))
        if inserted.isErr() { return Err(inserted.error()) }
        return Err(sqlInvalidArgument("rolled back"))
    }

    @Transactional
    Result<Long, Error> failTx(SqlTransaction tx) {
        return Err(sqlInvalidArgument("boom"))
    }

    @Transactional(true)
    Result<Long, Error> readOnlyTx(SqlTransaction tx) {
        return Ok(1)
    }
}
