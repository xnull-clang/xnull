// 容器（M4.4a）：数组/List/Map/Set 基础操作与遍历。
// 完成定义锚点：本示例经编译路径与解释路径输出逐字节一致。

static Int sum(Int[] xs) {
    Int total = 0;
    for v in xs {
        total = total + v;
    }
    return total;
}

static Int main() {
    Int[] nums = [1, 2, 3, 4];
    print(nums.length());
    print(nums[0] + nums[3]);
    print(sum(nums));

    nums[1] = 20;
    print(nums[1]);

    List<Int> buf = [5];
    buf.push(6);
    buf.push(7);
    print(buf.length());
    print(buf.get(0) + buf.get(2));

    Map<String, Int> scores = ["amy": 90, "bob": 85];
    print(scores.length());
    print(scores.getOr("amy", 0));
    print(scores.getOr("carl", 0));
    scores.put("carl", 70);
    print(scores.length());
    print(scores.has("carl"));
    print(scores.getOr("carl", 0));

    Set<Int> seen = [3, 1, 3];
    print(seen.length());
    print(seen.add(2));
    print(seen.add(1));
    print(seen.length());
    print(seen.has(2));

    return 0;
}
