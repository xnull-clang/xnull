package xfront

import (
	"fmt"
	"reflect"
	"strconv"
	"strings"

	"xnull.dev/xnull/internal/diag"
)

// B2-00：oracle 格式 v1（token/AST/诊断）。
//
// 采用反射式全字段序列化：结构体字段按声明顺序全部输出，切片保持顺序，
// 指针/接口输出具体类型；不依赖 map 迭代。这样新增 AST 字段不会静默漏出，
// 字段覆盖由结构本身保证（测试再做抽样守门）。

// DefaultDumpDepth 是 xnast AST dump 的默认深度上限。超过上限输出
// "(depth-limit)"（frontbridge 据此回退 Go oracle；B3-09 门禁禁止截断 AST）。
const DefaultDumpDepth = 4096

// PrintTokens 输出 token 流（一行一 token，含全部 Token 字段与位置）。
func PrintTokens(toks []Token) string {
	var b strings.Builder
	b.WriteString("xnast-tokens v1\n")
	for i := range toks {
		b.WriteString(dumpValue(reflect.ValueOf(toks[i])))
		b.WriteByte('\n')
	}
	return b.String()
}

// PrintUnitPos 输出完整 AST（含位置与全部字段）。
func PrintUnitPos(u *CompilationUnit) string {
	return PrintUnitPosDepth(u, DefaultDumpDepth)
}

// PrintUnitPosDepth 输出完整 AST，dump 深度上限为 depthLimit（<=0 时使用默认值）。
func PrintUnitPosDepth(u *CompilationUnit, depthLimit int) string {
	if depthLimit <= 0 {
		depthLimit = DefaultDumpDepth
	}
	return "(xnast v1 " + dumpReflect(reflect.ValueOf(u), 0, depthLimit) + ")"
}

// PrintDiags 输出诊断全集（含位置/码/消息/路径/hint）。
func PrintDiags(ds []diag.Diagnostic) string {
	var b strings.Builder
	b.WriteString("xnast-diags v1\n")
	for i := range ds {
		b.WriteString(dumpValue(reflect.ValueOf(ds[i])))
		b.WriteByte('\n')
	}
	return b.String()
}

// DumpValue 是调试/测试用的稳定值序列化。
func DumpValue(v any) string { return dumpValue(reflect.ValueOf(v)) }

func dumpValue(v reflect.Value) string {
	return dumpReflect(v, 0, DefaultDumpDepth)
}

func dumpReflect(v reflect.Value, depth, limit int) string {
	if depth > limit {
		return "(depth-limit)"
	}
	if !v.IsValid() {
		return "(nil)"
	}
	switch v.Kind() {
	case reflect.Interface:
		if v.IsNil() {
			return "(nil)"
		}
		return dumpReflect(v.Elem(), depth+1, limit)
	case reflect.Pointer:
		if v.IsNil() {
			return "(nil)"
		}
		return dumpReflect(v.Elem(), depth+1, limit)
	case reflect.Struct:
		t := v.Type()
		var b strings.Builder
		b.WriteString("(" + t.Name())
		for i := 0; i < v.NumField(); i++ {
			f := t.Field(i)
			if f.PkgPath != "" { // 未导出字段
				continue
			}
			b.WriteString(" (" + f.Name + " ")
			b.WriteString(dumpReflect(v.Field(i), depth+1, limit))
			b.WriteString(")")
		}
		b.WriteString(")")
		return b.String()
	case reflect.Slice:
		if v.IsNil() {
			return "(slice)"
		}
		var b strings.Builder
		b.WriteString("(slice")
		for i := 0; i < v.Len(); i++ {
			b.WriteString(" ")
			b.WriteString(dumpReflect(v.Index(i), depth+1, limit))
		}
		b.WriteString(")")
		return b.String()
	case reflect.String:
		return strconv.Quote(v.String())
	case reflect.Bool:
		if v.Bool() {
			return "true"
		}
		return "false"
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		return strconv.FormatInt(v.Int(), 10)
	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64:
		return strconv.FormatUint(v.Uint(), 10)
	case reflect.Float32, reflect.Float64:
		return strconv.FormatFloat(v.Float(), 'g', -1, 64)
	default:
		return fmt.Sprintf("(%s)", v.Kind())
	}
}
