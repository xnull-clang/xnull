// containers.go 是容器代码生成：按需实例化数组/List/Map/Set 的
// GC 对象与静态助手（每元素类型一份，无运行期注册表——P-03 评审结论）。
//
// 表示（S3 §10，ADR-007）：
//
//	xn_arr_<e>   { rt_header hdr; size_t len, cap; <e> *data; }   T[] / List<T>
//	xn_set_<e>   { rt_header hdr; xn_arr_<e> *a; }                 Set<T>（add 去重）
//	xn_map_<k>_<v> { rt_header hdr; size_t len, cap; <k> *keys; <v> *vals; }  Map<K,V>
//
// 生命周期：三者均为 GC 对象（xn_gc_new + 类型描述符 scan/deinit）；局部不 release、
// 不 free；元素区由容器 deinit 释放。ARC 元素入容器 retain、覆盖/移除/clear 时
// release；GC 元素只登记扫描（不计数）。元素扫描区由生成的 scan 钩子遍历。
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
	// 元组元素（S1 §2.11）：xn_tup_<...> → t_<...>（containerElem 可逆）。
	if strings.HasPrefix(c, "xn_tup_") {
		return "t_" + strings.TrimPrefix(c, "xn_tup_"), nil
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
func isRef(c string) bool {
	return c == "rt_string *" || c == "xrt_bytes_obj *" || c == "xrt_text *" || c == "xrt_sb *" || isClassPtr(c)
}

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

// optName 是可空类型 T? 的 C 表示（M6-B0-05：Int/Bool/String）。
func optName(c string) (string, error) {
	switch c {
	case "int64_t":
		return "xn_opt_i", nil
	case "int":
		return "xn_opt_b", nil
	case "rt_string *":
		return "xn_opt_s", nil
	case "xrt_handle *":
		// B0-07c：可空句柄不加 wrapper 结构，直接用指针的 NULL 哨兵。
		// 收窄（File? → File）后 C 类型不变，由 sema 负责流敏感判定。
		return "xrt_handle *", nil
	}
	return "", fmt.Errorf("codegen：可空类型 %s 未支持（M6-B0-05 范围：Int/Bool/String/handle）", c)
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

// emit 生成全部实例化的结构定义与静态助手（排序保证确定性输出）。
func (cs *containers) emit(b *strings.Builder, isGC func(string) bool) {
	var kinds []string
	for e := range cs.arr {
		kinds = append(kinds, e)
	}
	sort.Strings(kinds)
	for _, e := range kinds {
		emitArrHelpers(b, e, isGC(e))
	}
	var keys []string
	for k := range cs.set {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, e := range keys {
		emitSetHelpers(b, e, isGC(e))
	}
	var mkeys []string
	for k := range cs.mp {
		mkeys = append(mkeys, k)
	}
	sort.Strings(mkeys)
	for _, k := range mkeys {
		pair := cs.mp[k]
		emitMapHelpers(b, pair[0], pair[1], isGC(pair[0]), isGC(pair[1]))
	}
}

// emitArrHelpers 生成 T[]/List<T> 的 GC 对象（S3 §10：分配头 + 长度 + 元素区）。
func emitArrHelpers(b *strings.Builder, elem string, gcElem bool) {
	n := arrName(elem)
	ref := isRef(elem)
	arc := ref && !gcElem
	scanFn := "NULL"
	if ref {
		scanFn = n + "_scan"
	}
	scanBody := ""
	if ref {
		scanBody = fmt.Sprintf(`static void %[1]s_scan(void *p, void (*visit)(void *)) {
    %[1]s *a = (%[1]s *)p;
    if (a->data == NULL) { return; }
    for (size_t i = 0; i < a->len; i++) { visit(a->data[i]); }
}

`, n)
	}
	relBody := ""
	if arc {
		relBody = "        for (size_t i = 0; i < a->len; i++) { rt_release(a->data[i]); }\n"
	}
	keep := ""
	if arc {
		keep = "    rt_retain(v);\n"
	}
	dropOld := ""
	if arc {
		dropOld = "    rt_release(a->data[i]);\n"
	}
	clearRel := ""
	if arc {
		clearRel = "    for (size_t i = 0; i < a->len; i++) { rt_release(a->data[i]); }\n"
	}
	// join：元素字符串化后按分隔符连接（与解释器 format 一致）。
	elemStr := ""
	switch elem {
	case "int64_t":
		elemStr = "xn_str_int(a->data[i])"
	case "int":
		elemStr = "xn_str_bool(a->data[i])"
	case "rt_string *":
		elemStr = "rt_string_new(a->data[i]->bytes, a->data[i]->len)"
	default:
		elemStr = "rt_string_from_c(\"\")"
	}
	fmt.Fprintf(b, `typedef struct { rt_header hdr; size_t len; size_t cap; %[2]s *data; } %[1]s;

%[9]sstatic void %[1]s_deinit(void *p) {
    %[1]s *a = (%[1]s *)p;
    if (a->data != NULL) {
%[10]s        free(a->data);
        a->data = NULL;
    }
    a->len = 0;
    a->cap = 0;
}

static const rt_type RT_TYPE_%[1]s = { "List", sizeof(%[1]s), %[1]s_deinit, %[11]s };

static %[1]s *%[1]s_new(size_t cap) {
    %[1]s *a = (%[1]s *)xn_gc_new(&RT_TYPE_%[1]s);
    memset((char *)a + sizeof(rt_header), 0, sizeof(%[1]s) - sizeof(rt_header));
    a->cap = cap ? cap : 4;
    a->data = malloc(sizeof(%[2]s) * a->cap);
    if (a->data == NULL) { abort(); }
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

static %[2]s %[1]s_remove(%[1]s *a, int64_t i) {
    if (i < 0 || (size_t)i >= a->len) { xn_fatal_oob(); }
    %[2]s old = a->data[i];
    for (size_t j = (size_t)i; j + 1 < a->len; j++) {
        a->data[j] = a->data[j + 1];
    }
    a->len--;
    return old;
}

static void %[1]s_insert(%[1]s *a, int64_t i, %[2]s v) {
    if (i < 0 || (size_t)i > a->len) { xn_fatal_oob(); }
    if (a->len == a->cap) {
        a->cap *= 2;
        a->data = realloc(a->data, sizeof(%[2]s) * a->cap);
        if (a->data == NULL) { abort(); }
    }
    for (size_t j = a->len; j > (size_t)i; j--) {
        a->data[j] = a->data[j - 1];
    }
%[5]s    a->data[i] = v;
    a->len++;
}

static void %[1]s_clear(%[1]s *a) {
%[7]s    a->len = 0;
}

static rt_string *%[1]s_join(%[1]s *a, rt_string *sep) {
    rt_string *res = rt_string_from_c("");
    for (size_t i = 0; i < a->len; i++) {
        if (i > 0) {
            res = xn_concat(res, rt_string_new(sep->bytes, sep->len));
        }
        res = xn_concat(res, %[8]s);
    }
    return res;
}

`, n, elem, "", "", keep, dropOld, clearRel, elemStr, scanBody, relBody, scanFn)
}

// emitSetHelpers 生成 Set<T> 的 GC 对象（内部持有数组对象）。
func emitSetHelpers(b *strings.Builder, elem string, gcElem bool) {
	an := arrName(elem)
	sn := setName(elem)
	arc := isRef(elem) && !gcElem
	var eq string
	if isRef(elem) {
		eq = "s->a->data[i]->len == v->len && memcmp(s->a->data[i]->bytes, v->bytes, v->len) == 0"
	} else {
		eq = "s->a->data[i] == v"
	}
	dropRemoved := ""
	if arc {
		dropRemoved = "            rt_release(s->a->data[i]);\n"
	}
	fmt.Fprintf(b, `typedef struct { rt_header hdr; %[1]s *a; } %[2]s;

static void %[2]s_scan(void *p, void (*visit)(void *)) {
    %[2]s *s = (%[2]s *)p;
    if (s->a != NULL) { visit(s->a); }
}

static void %[2]s_deinit(void *p) {
    %[2]s *s = (%[2]s *)p;
    s->a = NULL; /* 数组是 GC 对象，由 GC 回收 */
}

static const rt_type RT_TYPE_%[2]s = { "Set", sizeof(%[2]s), %[2]s_deinit, %[2]s_scan };

static %[2]s *%[2]s_new(void) {
    %[2]s *s = (%[2]s *)xn_gc_new(&RT_TYPE_%[2]s);
    memset((char *)s + sizeof(rt_header), 0, sizeof(%[2]s) - sizeof(rt_header));
    s->a = %[1]s_new(4);
    return s;
}

static int %[2]s_add(%[2]s *s, %[3]s v) {
    for (size_t i = 0; i < s->a->len; i++) {
        if (%[4]s) { return 0; }
    }
    %[1]s_push(s->a, v);
    return 1;
}

static int %[2]s_has(const %[2]s *s, %[3]s v) {
    for (size_t i = 0; i < s->a->len; i++) {
        if (%[4]s) { return 1; }
    }
    return 0;
}

static %[3]s %[2]s_at(const %[2]s *s, int64_t i) {
    if (i < 0 || (size_t)i >= s->a->len) { xn_fatal_oob(); }
    return s->a->data[i];
}

static int %[2]s_remove(%[2]s *s, %[3]s v) {
    for (size_t i = 0; i < s->a->len; i++) {
        if (%[4]s) {
            for (size_t j = i; j + 1 < s->a->len; j++) {
                s->a->data[j] = s->a->data[j + 1];
            }
%[6]s            s->a->len--;
            return 1;
        }
    }
    return 0;
}

static void %[2]s_clear(%[2]s *s) { %[1]s_clear(s->a); }

`, an, sn, elem, eq, "", dropRemoved)
}

// emitMapHelpers 生成 Map<K,V> 的 GC 对象（keys/vals 元素区登记扫描）。
func emitMapHelpers(b *strings.Builder, k, v string, gcK, gcV bool) {
	n := mapName(k, v)
	arcK := isRef(k) && !gcK
	arcV := isRef(v) && !gcV
	var keq string
	if isRef(k) {
		keq = "m->keys[i]->len == key->len && memcmp(m->keys[i]->bytes, key->bytes, key->len) == 0"
	} else {
		keq = "m->keys[i] == key"
	}
	keepK, dropK := "", ""
	if arcK {
		keepK = "    rt_retain(key);\n"
		dropK = "    rt_release(m->keys[i]);\n"
	}
	keepV, dropV := "", ""
	if arcV {
		keepV = "    rt_retain(val);\n"
		dropV = "    rt_release(m->vals[i]);\n"
	}
	relK, relV := "", ""
	if arcK {
		relK = "        for (size_t i = 0; i < m->len; i++) { rt_release(m->keys[i]); }\n"
	}
	if arcV {
		relV = "        for (size_t i = 0; i < m->len; i++) { rt_release(m->vals[i]); }\n"
	}
	scanKeys, scanVals := "", ""
	if isRef(k) {
		scanKeys = "    if (m->keys != NULL) { for (size_t i = 0; i < m->len; i++) { visit(m->keys[i]); } }\n"
	}
	if isRef(v) {
		scanVals = "    if (m->vals != NULL) { for (size_t i = 0; i < m->len; i++) { visit(m->vals[i]); } }\n"
	}
	fmt.Fprintf(b, `typedef struct { rt_header hdr; size_t len; size_t cap; %[2]s *keys; %[3]s *vals; } %[1]s;

static void %[1]s_scan(void *p, void (*visit)(void *)) {
    %[1]s *m = (%[1]s *)p;
%[11]s%[12]s}

static void %[1]s_deinit(void *p) {
    %[1]s *m = (%[1]s *)p;
    if (m->keys != NULL) {
%[13]s        free(m->keys);
        m->keys = NULL;
    }
    if (m->vals != NULL) {
%[14]s        free(m->vals);
        m->vals = NULL;
    }
    m->len = 0;
    m->cap = 0;
}

static const rt_type RT_TYPE_%[1]s = { "Map", sizeof(%[1]s), %[1]s_deinit, %[1]s_scan };

static %[1]s *%[1]s_new(size_t cap) {
    %[1]s *m = (%[1]s *)xn_gc_new(&RT_TYPE_%[1]s);
    memset((char *)m + sizeof(rt_header), 0, sizeof(%[1]s) - sizeof(rt_header));
    m->cap = cap ? cap : 4;
    m->keys = malloc(sizeof(%[2]s) * m->cap);
    m->vals = malloc(sizeof(%[3]s) * m->cap);
    if (m->keys == NULL || m->vals == NULL) { abort(); }
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

`, n, k, v, relK, relV, keq, keepK, dropK, dropV, keepV, scanKeys, scanVals, relK, relV)

	// 排序键（DET-01）...
	cmpBody := ""
	switch k {
	case "rt_string *":
		cmpBody = `    size_t n = a->len < b->len ? a->len : b->len;
    int c = memcmp(a->bytes, b->bytes, n);
    if (c != 0) { return c; }
    return (a->len > b->len) - (a->len < b->len);`
	case "int64_t":
		cmpBody = `    char ba[32], bb[32];
    snprintf(ba, sizeof(ba), "%lld", (long long)a);
    snprintf(bb, sizeof(bb), "%lld", (long long)b);
    return strcmp(ba, bb);`
	case "int":
		cmpBody = `    return (a > b) - (a < b);`
	default:
		cmpBody = `    return 0;`
	}
	fmt.Fprintf(b, `static int %[1]s_cmp_key(%[2]s a, %[2]s b) {
%[3]s
}

static void %[1]s_sort_idx(const %[1]s *m, size_t *idx) {
    for (size_t i = 1; i < m->len; i++) {
        size_t x = idx[i];
        size_t j = i;
        while (j > 0 && %[1]s_cmp_key(m->keys[idx[j - 1]], m->keys[x]) > 0) {
            idx[j] = idx[j - 1];
            j--;
        }
        idx[j] = x;
    }
}

static %[4]s *%[1]s_keys(const %[1]s *m) {
    %[4]s *out = %[4]s_new(m->len);
    if (m->len == 0) { return out; }
    size_t *idx = malloc(sizeof(size_t) * m->len);
    if (idx == NULL) { abort(); }
    for (size_t i = 0; i < m->len; i++) { idx[i] = i; }
    %[1]s_sort_idx(m, idx);
    for (size_t i = 0; i < m->len; i++) { %[4]s_push(out, m->keys[idx[i]]); }
    free(idx);
    return out;
}

static %[5]s *%[1]s_values(const %[1]s *m) {
    %[5]s *out = %[5]s_new(m->len);
    if (m->len == 0) { return out; }
    size_t *idx = malloc(sizeof(size_t) * m->len);
    if (idx == NULL) { abort(); }
    for (size_t i = 0; i < m->len; i++) { idx[i] = i; }
    %[1]s_sort_idx(m, idx);
    for (size_t i = 0; i < m->len; i++) { %[5]s_push(out, m->vals[idx[i]]); }
    free(idx);
    return out;
}

`, n, k, cmpBody, arrName(k), arrName(v))
	if ov, err := optName(v); err == nil {
		zero := elemZero(v)
		retainV := ""
		if arcV {
			retainV = "    rt_retain(r.v);\n"
		}
		fmt.Fprintf(b, `static %[3]s %[1]s_get(const %[1]s *m, %[2]s key) {
    %[3]s r;
    long i = %[1]s_find(m, key);
    if (i < 0) { r.has = 0; r.v = %[4]s; return r; }
    r.has = 1;
    r.v = m->vals[i];
%[5]s    return r;
}

`, n, k, ov, zero, retainV)
	}
}

// ensureMapArrays 保证 Map 的 keys/values 助手可编译（数组实例化在 Map 之后登记）。
func (cs *containers) ensureMapArrays() {
	for _, kv := range cs.mp {
		cs.arr[kv[0]] = true
		cs.arr[kv[1]] = true
	}
}

// relElemLoop 生成释放全部元素引用的语句（非引用元素为空）。
func relElemLoop(elem string) string {
	if isRef(elem) {
		return "    for (size_t i = 0; i < a->len; i++) { rt_release(a->data[i]); }\n"
	}
	return ""
}

// strSplitHelper 是 String.split 的 C 助手（字节语义，与解释器 §9.2 一致）。
const strSplitHelper = `
static xn_arr_s *xn_str_split(rt_string *s, rt_string *sep) {
    xn_arr_s *out = xn_arr_s_new(4);
    if (sep->len == 0) {
        rt_string *t = rt_string_new(s->bytes, s->len);
        xn_arr_s_push(out, t);
        rt_release(t);
        return out;
    }
    size_t start = 0, i = 0;
    while (i + sep->len <= s->len) {
        if (memcmp(s->bytes + i, sep->bytes, sep->len) == 0) {
            rt_string *t = rt_string_new(s->bytes + start, i - start);
            xn_arr_s_push(out, t);
            rt_release(t);
            i += sep->len;
            start = i;
        } else {
            i++;
        }
    }
    rt_string *last = rt_string_new(s->bytes + start, s->len - start);
    xn_arr_s_push(out, last);
    rt_release(last);
    return out;
}
`

// strReplaceHelper 是 String.replace 的 C 助手（ReplaceAll 语义，字节匹配）。
const strReplaceHelper = `
static rt_string *xn_str_replace(rt_string *s, rt_string *from, rt_string *to) {
    if (from->len == 0) { return rt_retain(s); }
    rt_string *res = rt_string_from_c("");
    size_t start = 0, i = 0;
    while (i + from->len <= s->len) {
        if (memcmp(s->bytes + i, from->bytes, from->len) == 0) {
            res = xn_concat(res, rt_string_new(s->bytes + start, i - start));
            res = xn_concat(res, rt_string_new(to->bytes, to->len));
            i += from->len;
            start = i;
        } else {
            i++;
        }
    }
    res = xn_concat(res, rt_string_new(s->bytes + start, s->len - start));
    return res;
}
`
