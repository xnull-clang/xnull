#include <stdio.h>
#include <string.h>

char *xdkc_md5_hex(const char *data, size_t n);
char *xdkc_sha1_hex(const char *data, size_t n);
char *xdkc_sha256_hex(const char *data, size_t n);
char *xdkc_sha512_hex(const char *data, size_t n);

static int failures = 0;

static void check(const char *label, const char *actual, const char *expected) {
    if (strcmp(actual, expected) != 0) {
        fprintf(stderr, "FAIL %s\n  actual:   %s\n  expected: %s\n", label, actual, expected);
        failures++;
    } else {
        printf("PASS %s %s\n", label, actual);
    }
}

int main(void) {
    unsigned char longData[200];
    for (int i = 0; i < 200; i++) longData[i] = (unsigned char)i;

    check("md5-empty", xdkc_md5_hex("", 0),
          "d41d8cd98f00b204e9800998ecf8427e");
    check("md5-abc", xdkc_md5_hex("abc", 3),
          "900150983cd24fb0d6963f7d28e17f72");
    check("md5-long", xdkc_md5_hex((const char *)longData, 200),
          "fb7001d34b8e82c9b579be5005d5b0a5");

    check("sha1-empty", xdkc_sha1_hex("", 0),
          "da39a3ee5e6b4b0d3255bfef95601890afd80709");
    check("sha1-abc", xdkc_sha1_hex("abc", 3),
          "a9993e364706816aba3e25717850c26c9cd0d89d");
    check("sha1-long", xdkc_sha1_hex((const char *)longData, 200),
          "54d11e99127d159799dbce10f51a75e697780478");

    check("sha256-empty", xdkc_sha256_hex("", 0),
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    check("sha256-abc", xdkc_sha256_hex("abc", 3),
          "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    check("sha256-long", xdkc_sha256_hex((const char *)longData, 200),
          "1901da1c9f699b48f6b2636e65cbf73abf99d0441ef67f5c540a42f7051dec6f");

    check("sha512-empty", xdkc_sha512_hex("", 0),
          "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce"
          "47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e");
    check("sha512-abc", xdkc_sha512_hex("abc", 3),
          "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
          "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f");
    check("sha512-long", xdkc_sha512_hex((const char *)longData, 200),
          "986058e9895e2c2ab8f9e8cbdf801db12a44842a56a91d5a4e87b1fc98b29372"
          "2c4664142e42c3c551ff898646268cd92b84ed230b8c94bed7798d4f27cd7465");

    if (failures != 0) {
        fprintf(stderr, "test_crypto: %d failure(s)\n", failures);
        return 1;
    }
    printf("test_crypto: PASS\n");
    return 0;
}
