// xdk.math —— 对标 Go math + Python math/statistics/random 的基础数学包。
// 超越函数与随机数经 ext_raw 桥接 libm / xorshift64*；统计与数论为纯源码实现。
// 约定：Double 版函数沿用脑图命名；整数版加 I 后缀（absI/minI/maxI/clampI）。
package xdk.math













































































































































































































































































































































































































class Random {
    Int64 s

    Random(Int64 seed) {
        self.s = seed
        randSeedRaw(seed)
    }

    Int nextInt(Int bound) {
        if bound <= 0 {
            return 0
        }
        return randNextRaw() % bound
    }

    Double nextDouble() {
        return randDoubleRaw()
    }

    Bool nextBool() {
        return randNextRaw() % 2 == 0
    }

    // 原地 Fisher-Yates（List<String>）。
    void shuffle(List<String> xs) {
        Int i = xs.length() - 1
        while i > 0 {
            Int j = randNextRaw() % (i + 1)
            String t = xs.get(i)
            xs.set(i, xs.get(j))
            xs.set(j, t)
            i = i - 1
        }
    }

    String choice(List<String> xs) {
        if xs.length() == 0 {
            return ""
        }
        return xs.get(randNextRaw() % xs.length())
    }

    // 原地 Fisher-Yates（List<Int>）。
    void shuffleInts(List<Int> xs) {
        Int i = xs.length() - 1
        while i > 0 {
            Int j = randNextRaw() % (i + 1)
            Int t = xs.get(i)
            xs.set(i, xs.get(j))
            xs.set(j, t)
            i = i - 1
        }
    }

    Int choiceInt(List<Int> xs) {
        if xs.length() == 0 {
            return 0
        }
        return xs.get(randNextRaw() % xs.length())
    }
}
