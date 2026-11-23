package app.sql
import xdk.sql

@Row
class UserRow {
    @Column("user_id")
    Long id
    @Column("display_name")
    String name
    Bool active
    Double score
    UserRow(Long id, String name, Bool active, Double score) {
        self.id = id
        self.name = name
        self.active = active
        self.score = score
    }
}

class UserDao {
    @Sql("SELECT user_id, display_name, active, score FROM users WHERE user_id = :id")
    Result<UserRow, Error> find(@Param("id") Long id) {
        return Err(sqlInvalidArgument("stub"))
    }

    @Sql("SELECT display_name, user_id, active, score FROM users WHERE user_id = :id")
    Result<UserRow, Error> findReordered(Long id) {
        return Err(sqlInvalidArgument("stub"))
    }

    @Sql("SELECT user_id, display_name, active, score FROM users WHERE display_name = :name AND user_id = :id")
    Result<UserRow, Error> findByNameAndId(@Param("id") Long id, @Param("name") String name) {
        return Err(sqlInvalidArgument("stub"))
    }

    @Sql("SELECT user_id, display_name, active, score FROM users")
    Result<List<UserRow>, Error> list() {
        return Err(sqlInvalidArgument("stub"))
    }

    @Sql("INSERT INTO users VALUES (:id, :name, :active, :score)")
    Result<Long, Error> insert(@Param("id") Long id, @Param("name") String name, @Param("active") Bool active, @Param("score") Double score) {
        return Err(sqlInvalidArgument("stub"))
    }

    @Sql("UPDATE users SET display_name = :name WHERE user_id = :id")
    Result<Long, Error> update(@Param("name") String name, @Param("id") Long id) {
        return Err(sqlInvalidArgument("stub"))
    }

    @Sql("SELECT user_id, display_name, active, score FROM users WHERE display_name = :name")
    Result<List<UserRow>, Error> byName(String name) {
        return Err(sqlInvalidArgument("stub"))
    }
}
