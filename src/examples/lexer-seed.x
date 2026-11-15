// 自举素材 #1（M5.1）：XNull 实现的词法扫描器（子集起步）。
//
// 只使用当前已落地的语言面：类 + 字段 + 方法 + String 成员（length/substring/indexOf/toLower）
// + while + if/else + 字符串拼接。不依赖枚举/闭包/元组——这些随自举推进按需补。
//
// 完成定义锚点：本示例经编译路径与解释路径输出逐字节一致。

class Scan {
    String src;
    Int pos = 0;
    Int ntoks = 0;

    Bool eof() {
        return self.pos >= self.src.length();
    }

    String at() {
        return self.src.substring(self.pos, 1);
    }

    Bool isDigit(String c) {
        return "0123456789".indexOf(c) >= 0;
    }

    Bool isAlpha(String c) {
        return "abcdefghijklmnopqrstuvwxyz_".indexOf(c.toLower()) >= 0;
    }

    Bool isSpace(String c) {
        return " \t\n\r".indexOf(c) >= 0;
    }

    Bool isSym(String c) {
        return "(){}[],;.=+-*/<>!&|:".indexOf(c) >= 0;
    }

    void emit(String kind, String text) {
        print(kind + ":" + text);
        self.ntoks = self.ntoks + 1;
    }

    void scan() {
        while (!self.eof()) {
            String c = self.at();
            if (self.isSpace(c)) {
                self.pos = self.pos + 1;
            } else if (self.isAlpha(c)) {
                String t = "";
                Bool cont = !self.eof() && self.isAlpha(self.at());
                while (cont) {
                    String ch = self.at();
                    t = t + ch;
                    self.pos = self.pos + 1;
                    cont = !self.eof() && (self.isAlpha(self.at()) || self.isDigit(self.at()));
                }
                self.emit("id", t);
            } else if (self.isDigit(c)) {
                String t = "";
                while (!self.eof() && self.isDigit(self.at())) {
                    String ch = self.at();
                    t = t + ch;
                    self.pos = self.pos + 1;
                }
                self.emit("num", t);
            } else if (self.isSym(c)) {
                self.pos = self.pos + 1;
                self.emit("sym", c);
            } else {
                self.pos = self.pos + 1;
                self.emit("err", c);
            }
        }
    }
}

static Int main() {
    Scan s = new Scan();
    s.src = "let total = 42 + x1;";
    s.scan();
    print(s.ntoks);
    print(s.pos);
    return 0;
}
