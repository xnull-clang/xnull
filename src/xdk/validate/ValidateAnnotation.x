// @Validate marks a type whose fields are validated by generated Schema.
// The canonical package implementation already occupies Validate.x, so the
// annotation declaration lives in this PascalCase sibling file.
package xdk.validate
import xdk.annotations

@Retention(Source)
@Target(Type)
@annotation Validate {
}
