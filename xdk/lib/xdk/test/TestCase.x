// @TestCase: generate an explicit TestSuite entry for a no-argument test method.
package xdk.test
import xdk.annotations

@Retention(Runtime)
@Target(Method)
@annotation TestCase {
    final String name = ""
}
