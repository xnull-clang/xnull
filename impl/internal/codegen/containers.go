// containers.go 是 M4.4a 容器代码生成：按需实例化数组/List/Map/Set 的
// C 结构与静态助手（每元素类型一份，无运行期注册表——P-03 评审结论）。
//
// 表示（codegen 私有，不进运行时 ABI）：
//
//	xn_arr_<e>   { size_t len, cap; <e> *data; }   T[] / List<T>
//	xn_set_<e>   { xn_arr_<e> a; }                 Set<T>（add 去重）
//	xn_map_<k>_<v> { size_t len, cap; <k> *keys; <v> *vals; }  Map<K,V>
//
// 所有权：局部容器在作用域退出时 free（本层 deferItem）；函数参数为借用
// （不 free）；元素为 String 时，入容器 retain、覆盖/移除/free 时 release；
// 读取成员（get/first）返回借用指针，调用方若需长期持有须自行策略。
// Map 键序：插入序（keys() 未纳入 4.4a 面，DET-01 不受影响）。
package codegen

import (
	"fmt"
	"sort"
	"strings"
)

// mangle 把 C 类型映射为实例化后缀：int64_t→i、int→b、rt_string*→s。
func mangle(c string) (string, error) {
	switch c {
	case "int64_t":
		return "i", nil
	case "int":
		return "b", nil
	case "rt_string *":
		return "s", nil
	}
	// 类引用元素（M5.1-a：自举 AST 需要 List<Node>）：xn_Cls_X * → o_X
	if isClassPtr(c) {
		return "o_" + strings.TrimSuffix(strings.TrimPrefix(c, "xn_Cls_"), " *"), nil
	}
	return "", fmt.Errorf("codegen：容器元素类型暂支持 Int/Bool/String/类引用（M5.1-a 范围），got %s", c)
}

func elemZero(c string) string {
	if isRef(c) {
		return "NULL"
	}
	return "0"
}

// isRef 判断元素类型是否引用（需 retain/release；ARC 对象与字符串同一纪律）。
func isRef(c string) bool { return c == "rt_string *" || isClassPtr(c) }

// containers 收集本次翻译单元需要的实例化，并给出生成文本。
type containers struct {
	arr map[string]bool // 元素 C 类型
	set map[string]bool
	mp  map[string][2]string // "k|v" → {k, v}
}

func newContainers() *containers {
	return &containers{arr: map[string]bool{}, set: map[string]bool{}, mp: map[string][2]string{}}
}

func (cs *containers) needArr(elem string) error {
	if _, err := mangle(elem); err != nil {
		return err
	}
	cs.arr[elem] = true
	return nil
}

func (cs *containers) needSet(elem string) error {
	if err := cs.needArr(elem); err != nil {
		return err
	}
	cs.set[elem] = true
	return nil
}

func (cs *containers) needMap(k, v string) error {
	km, err := mangle(k)
	if err != nil {
		return err
	}
	vm, err := mangle(v)
	if err != nil {
		return err
	}
	cs.mp[km+"|"+vm] = [2]string{k, v}
	return nil
}

func arrName(elem string) string {
	m, _ := mangle(elem)
	return "xn_arr_" + m
}

func setName(elem string) string {
	m, _ := mangle(elem)
	return "xn_set_" + m
}

func mapName(k, v string) string {
	km, _ := mangle(k)
	vm, _ := mangle(v)
	return "xn_map_" + km + "_" + vm
}

// emitForwardDecls 生成容器元素引用的类前向声明（typedef struct X X;）。
// 容器定义必须出现在类完整定义之前（输出顺序：容器在类之前），指针前向声明足够。
func (cs *containers) emitForwardDecls(b *strings.Builder) {
	seen := map[string]bool{}
	for elem := range cs.arr {
		seen[elem] = true
	}
	for elem := range cs.set {
		seen[elem] = true
	}
	for _, kv := range cs.mp {
		seen[kv[0]] = true
		seen[kv[1]] = true
	}
	var names []string
	for elem := range seen {
		m, err := mangle(elem)
		if err != nil || !strings.HasPrefix(m, "o_") {
			continue
		}
		names = append(names, strings.TrimPrefix(m, "o_"))
	}
	sort.Strings(names)
	for _, n := range names {
		fmt.Fprintf(b, "typedef struct xn_Cls_%s xn_Cls_%s;\n", n, n)
	}
	if len(names) > 0 {
		b.WriteString("\n")
	}
}

// emit 生成全部实例化的结构定义与静态助手（排序保证确定性输出）。
func (cs *containers) emit(b *strings.Builder) {
	var kinds []string
	for e := range cs.arr {
		kinds = append(kinds, e)
	}
	sort.Strings(kinds)
	for _, e := range kinds {
		emitArrHelpers(b, e)
	}
	var keys []string
	for k := range cs.set {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, e := range keys {
		emitSetHelpers(b, e)
	}
	var mkeys []string
	for k := range cs.mp {
		mkeys = append(mkeys, k)
	}
	sort.Strings(mkeys)
	for _, k := range mkeys {
		pair := cs.mp[k]
		emitMapHelpers(b, pair[0], pair[1])
	}
}

func emitArrHelpers(b *strings.Builder, elem string) {
	n := arrName(elem)
	zero := elemZero(elem)
	rel := "    free(a->data);\n"
	if isRef(elem) {
		rel = "    for (size_t i = 0; i < a->len; i++) { rt_release(a->data[i]); }\n    free(a->data);\n"
	}
	keep := ""
	if isRef(elem) {
		keep = "    rt_retain(v);\n"
	}
	dropOld := ""
	if isRef(elem) {
		dropOld = "    rt_release(a->data[i]);\n"
	}
	fmt.Fprintf(b, `typedef struct { size_t len; size_t cap; %[2]s *data; } %[1]s;

static %[1]s %[1]s_new(size_t cap) {
    %[1]s a;
    a.len = 0;
    a.cap = cap ? cap : 4;
    a.data = malloc(sizeof(%[2]s) * a.cap);
    if (a.data == NULL) { abort(); }
    return a;
}

static void %[1]s_push(%[1]s *a, %[2]s v) {
    if (a->len == a->cap) {
        a->cap *= 2;
        a->data = realloc(a->data, sizeof(%[2]s) * a->cap);
        if (a->data == NULL) { abort(); }
    }
%[5]s    a->data[a->len++] = v;
}

static %[2]s %[1]s_get(const %[1]s *a, int64_t i) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    return a->data[i];
}

static void %[1]s_set(%[1]s *a, int64_t i, %[2]s v) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
%[6]s%[5]s    a->data[i] = v;
}

static void %[1]s_remove(%[1]s *a, int64_t i) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
%[7]s    for (size_t j = (size_t)i; j + 1 < a->len; j++) {
        a->data[j] = a->data[j + 1];
    }
    a->len--;
}

static void %[1]s_clear(%[1]s *a) {
%[8]s    a->len = 0;
}

static void %[1]s_free(%[1]s *a) {
%[4]s    a->data = NULL;
    a->len = 0;
    a->cap = 0;
}

`, n, elem, "", rel, keep, dropOld,
		relElemLoop(elem), relElemLoop(elem))
	_ = zero
}

func emitSetHelpers(b *strings.Builder, elem string) {
	an := arrName(elem)
	sn := setName(elem)
	var eq string
	if isRef(elem) {
		eq = "s->a.data[i]->len == v->len && memcmp(s->a.data[i]->bytes, v->bytes, v->len) == 0"
	} else {
		eq = "s->a.data[i] == v"
	}
	fmt.Fprintf(b, `typedef struct { %[1]s a; } %[2]s;

static %[2]s %[2]s_new(void) {
    %[2]s s;
    s.a = %[1]s_new(4);
    return s;
}

static int %[2]s_add(%[2]s *s, %[3]s v) {
    for (size_t i = 0; i < s->a.len; i++) {
        if (%[4]s) { return 0; }
    }
    %[1]s_push(&s->a, v);
    return 1;
}

static int %[2]s_has(const %[2]s *s, %[3]s v) {
    for (size_t i = 0; i < s->a.len; i++) {
        if (%[4]s) { return 1; }
    }
    return 0;
}

static void %[2]s_free(%[2]s *s) { %[1]s_free(&s->a); }

`, an, sn, elem, eq)
}

func emitMapHelpers(b *strings.Builder, k, v string) {
	n := mapName(k, v)
	var keq string
	if isRef(k) {
		keq = "m->keys[i]->len == key->len && memcmp(m->keys[i]->bytes, key->bytes, key->len) == 0"
	} else {
		keq = "m->keys[i] == key"
	}
	keepK, dropK, freeK := "", "", "    free(m->keys);\n"
	if isRef(k) {
		keepK = "    rt_retain(key);\n"
		dropK = "    rt_release(m->keys[i]);\n"
		freeK = "    for (size_t i = 0; i < m->len; i++) { rt_release(m->keys[i]); }\n    free(m->keys);\n"
	}
	keepV, dropV, freeV := "", "", "    free(m->vals);\n"
	if isRef(v) {
		keepV = "    rt_retain(val);\n"
		dropV = "    rt_release(m->vals[i]);\n"
		freeV = "    for (size_t i = 0; i < m->len; i++) { rt_release(m->vals[i]); }\n    free(m->vals);\n"
	}
	fmt.Fprintf(b, `typedef struct { size_t len; size_t cap; %[2]s *keys; %[3]s *vals; } %[1]s;

static %[1]s %[1]s_new(size_t cap) {
    %[1]s m;
    m.len = 0;
    m.cap = cap ? cap : 4;
    m.keys = malloc(sizeof(%[2]s) * m.cap);
    m.vals = malloc(sizeof(%[3]s) * m.cap);
    if (m.keys == NULL || m.vals == NULL) { abort(); }
    return m;
}

static long %[1]s_find(const %[1]s *m, %[2]s key) {
    for (size_t i = 0; i < m->len; i++) {
        if (%[6]s) { return (long)i; }
    }
    return -1;
}

static void %[1]s_put(%[1]s *m, %[2]s key, %[3]s val) {
    long i = %[1]s_find(m, key);
    if (i >= 0) {
%[8]s%[9]s        m->vals[i] = val;
        return;
    }
    if (m->len == m->cap) {
        m->cap *= 2;
        m->keys = realloc(m->keys, sizeof(%[2]s) * m->cap);
        m->vals = realloc(m->vals, sizeof(%[3]s) * m->cap);
        if (m->keys == NULL || m->vals == NULL) { abort(); }
    }
%[7]s%[10]s    m->keys[m->len] = key;
    m->vals[m->len] = val;
    m->len++;
}

static int %[1]s_has(const %[1]s *m, %[2]s key) { return %[1]s_find(m, key) >= 0; }

static %[3]s %[1]s_get_or(const %[1]s *m, %[2]s key, %[3]s dflt) {
    long i = %[1]s_find(m, key);
    return i >= 0 ? m->vals[i] : dflt;
}

static int %[1]s_remove(%[1]s *m, %[2]s key) {
    long i = %[1]s_find(m, key);
    if (i < 0) { return 0; }
%[8]s%[9]s    for (size_t j = (size_t)i; j + 1 < m->len; j++) {
        m->keys[j] = m->keys[j + 1];
        m->vals[j] = m->vals[j + 1];
    }
    m->len--;
    return 1;
}

static void %[1]s_clear(%[1]s *m) {
%[4]s%[5]s    m->len = 0;
}

static void %[1]s_free(%[1]s *m) {
%[4]s%[5]s    m->len = 0;
    m->cap = 0;
}

`, n, k, v, freeK, freeV, keq, keepK, dropK, dropV, keepV)
}

// relElemLoop 生成释放全部元素引用的语句（非引用元素为空）。
func relElemLoop(elem string) string {
	if isRef(elem) {
		return "    for (size_t i = 0; i < a->len; i++) { rt_release(a->data[i]); }\n"
	}
	return ""
}
