#!/usr/bin/env python3
import os
import tempfile
import unittest

from package_resolver import (PackageResolver, ResolveError, imports_of,
                              merge_asts, package_of)


def unit(package="", declarations="", imports=""):
    pkg = "(nil)" if not package else (
        "(PackageDecl (P (Pos (Line 1) (Col 1))) (Name (slice %s)))" %
        " ".join('"%s"' % part for part in package.split(".")))
    imps = " ".join(
        "(ImportDecl (P (Pos (Line 2) (Col 1))) (Path (slice %s)) (Alias \"\"))" %
        " ".join('"%s"' % part for part in path.split("."))
        for path in imports)
    return ("(xnast v1 (CompilationUnit (P (Pos (Line 1) (Col 1))) "
            "(Package %s) (Imports (slice%s)) (Decls (slice%s))))" %
            (pkg, " " + imps if imps else "",
             " " + declarations if declarations else ""))


def class_decl(name):
    return "(ClassDecl (P (Pos (Line 1) (Col 1))) (Name \"%s\"))" % name


def func_decl(name):
    return "(TopFunc (P (Pos (Line 1) (Col 1))) (Name \"%s\"))" % name


class PackageResolverTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        self.xdk = os.path.join(self.root, "impl", "lib", "xdk")
        os.makedirs(self.xdk)
        self.resolver = PackageResolver(self.root, self.root)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, rel, text):
        path = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        return path

    def test_package_import_keeps_legacy_file(self):
        expected = self.write("lib/text.x", "legacy")
        found = self.resolver.resolve(["lib", "text"])
        self.assertEqual(found.package, "lib.text")
        self.assertEqual(found.files, (expected,))
        self.assertEqual(found.primary, expected)

    def test_class_import_aggregates_legacy_and_directory(self):
        legacy = self.write("impl/lib/xdk/core/time/Time.x", "legacy")
        duration = self.write("impl/lib/xdk/core/time/Duration.x", "class")
        found = self.resolver.resolve(["xdk", "time", "Duration"])
        self.assertEqual(found.package, "xdk.time")
        self.assertEqual(found.symbol, "Duration")
        self.assertEqual(found.files, (duration, legacy))
        asts = {
            legacy: unit("xdk.time", func_decl("nowMs"), ["xdk.errors"]),
            duration: unit("xdk.time", class_decl("Duration")),
        }
        units, slot = self.resolver.parse(found, lambda path: asts[path])
        self.assertEqual(len(units), 2)
        self.assertEqual(slot["path"], legacy)
        self.assertLess(slot["ast"].index("Duration"), slot["ast"].index("nowMs"))
        self.assertEqual(package_of(slot["ast"]), "xdk.time")
        self.assertEqual(imports_of(slot["ast"]), [["xdk", "errors"]])

    def test_class_file_must_declare_same_class(self):
        path = self.write("impl/lib/xdk/core/time/Duration.x", "class")
        found = self.resolver.resolve(["xdk", "time", "Duration"])
        with self.assertRaisesRegex(ResolveError, "同名 class Duration"):
            self.resolver.parse(found, lambda _path: unit("xdk.time", class_decl("Other")))

    def test_package_declaration_must_match_directory(self):
        self.write("impl/lib/xdk/core/time/Duration.x", "class")
        found = self.resolver.resolve(["xdk", "time", "Duration"])
        with self.assertRaisesRegex(ResolveError, "package 不匹配"):
            self.resolver.parse(found, lambda _path: unit("xdk.other", class_decl("Duration")))

    def test_missing_uppercase_class_does_not_fall_back_to_legacy(self):
        self.write("impl/lib/xdk/text/base/Text.x", "legacy")
        with self.assertRaisesRegex(ResolveError, "类文件不存在"):
            self.resolver.resolve(["xdk", "text", "Format"])

    def test_class_import_requires_package_name(self):
        with self.assertRaisesRegex(ResolveError, "必须包含包名"):
            self.resolver.resolve(["Duration"])

    def test_merge_rejects_two_named_packages(self):
        with self.assertRaisesRegex(ResolveError, "多个 package"):
            merge_asts([unit("lib.a", class_decl("A")),
                        unit("lib.b", class_decl("B"))])


if __name__ == "__main__":
    unittest.main()
