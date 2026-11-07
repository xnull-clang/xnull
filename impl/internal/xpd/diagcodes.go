package xpd

import (
	"fmt"

	"xnull.dev/xnull/internal/diag"
)

// S8-10/10b：XPD-2xx—8xx 稳定码位与固定文案模板（S8 附录 C.5）。
//
// 码位以实际校验器（manifest/config/plugin/resman/xmeta）的常量为准；
// 新增码只能落在既有段位内（跨段位属规范修订）。

// XDPSpec 是一个诊断码的类别与文案模板。
type XDPSpec struct {
	Code     string
	Category string
	Template string
}

var xpdCategories = map[byte]string{
	'0': "词法",
	'1': "文法与结构",
	'2': "段落与字段",
	'3': "坐标与继承",
	'4': "依赖与锁",
	'5': "插件",
	'6': "配置",
	'7': "元数据",
	'8': "资源与打包",
}

// CodeSpecs 是 2xx—8xx 的码位与模板；与校验器落点一一对应。
var CodeSpecs = []XDPSpec{
	{"XPD-201", "段落与字段", `未知段落/字段 %q`},
	{"XPD-202", "段落与字段", `段落或字段重复 %q`},
	{"XPD-203", "段落与字段", `容器段落含非法条目 %q`},

	{"XPD-301", "坐标与继承", `缺少坐标字段 %s`},
	{"XPD-302", "坐标与继承", `坐标重复：%s`},
	{"XPD-303", "坐标与继承", `继承深度超限：%s`},
	{"XPD-304", "坐标与继承", `继承环：%s`},
	{"XPD-305", "坐标与继承", `parent 缺失：%s`},
	{"XPD-306", "坐标与继承", `parent 必须是 pom：%s`},
	{"XPD-307", "坐标与继承", `未解析变量：%s`},
	{"XPD-308", "坐标与继承", `枚举变量值非法：%s`},
	{"XPD-309", "坐标与继承", `profile 激活/覆盖非法：%s`},

	{"XPD-401", "依赖与锁", `依赖缺少版本：%s`},
	{"XPD-402", "依赖与锁", `版本形态非法：%s`},
	{"XPD-403", "依赖与锁", `同层坐标冲突/管理表重复：%s`},
	{"XPD-404", "依赖与锁", `锁与清单不一致：%s`},
	{"XPD-405", "依赖与锁", `锁中坐标多余：%s`},
	{"XPD-406", "依赖与锁", `摘要格式/内容不符：%s`},
	{"XPD-407", "依赖与锁", `管理表出现 scope/optional：%s`},

	{"XPD-501", "插件", `phase/goal/configKeys/版本形态非法：%s`},
	{"XPD-502", "插件", `插件越界写 target 之外：%s`},
	{"XPD-503", "插件", `插件非零退出：%s`},
	{"XPD-504", "插件", `.xplugin 缺失或字段不符：%s`},
	{"XPD-505", "插件", `插件尝试网络访问：%s`},

	{"XPD-600", "配置", `配置文件格式/编码错误：%s`},
	{"XPD-601", "配置", `键名非法：%s`},
	{"XPD-602", "配置", `同层重复键：%s`},
	{"XPD-603", "配置", `未知键：%s`},
	{"XPD-604", "配置", `缺少必需键：%s`},
	{"XPD-605", "配置", `值类型解析失败：%s`},
	{"XPD-606", "配置", `疑似密钥写入配置：%s`},
	{"XPD-607", "配置", `profile 文件名与清单不符：%s`},
	{"XPD-608", "配置", `非 app 工程出现配置文件：%s`},

	{"XPD-701", "元数据", `.xmeta 缺字段：%s`},
	{"XPD-702", "元数据", `.xmeta 字段不符：%s`},
	{"XPD-703", "元数据", `工具链版本不符：%s`},

	{"XPD-801", "资源与打包", `资源根非法：%s`},
	{"XPD-802", "资源与打包", `glob 语法错：%s`},
	{"XPD-803", "资源与打包", `资源同路径冲突：%s`},
	{"XPD-804", "资源与打包", `pom 不得声明资源：%s`},
	{"XPD-805", "资源与打包", `符号链接断链/指向目录：%s`},
}

// CodeSpec 查码位规格。
func CodeSpec(code string) (XDPSpec, bool) {
	for _, s := range CodeSpecs {
		if s.Code == code {
			return s, true
		}
	}
	return XDPSpec{}, false
}

// NewDiag 按码位模板构造带段落路径的诊断；未知码位回退为通用文案。
func NewDiag(file string, pos Pos, code, path string, args ...any) diag.Diagnostic {
	msg := code
	if spec, ok := CodeSpec(code); ok {
		msg = spec.Template
		if len(args) > 0 {
			msg = fmt.Sprintf(spec.Template, args...)
		}
	} else if len(args) > 0 {
		msg = fmt.Sprintf("%v", args...)
	}
	return diag.Diagnostic{
		File: file, Line: pos.Line, Col: pos.Col,
		Code: code, Message: msg, Path: path,
	}
}

// SegmentOf 返回码位段位类别；未知返回空。
func SegmentOf(code string) string {
	if len(code) != 7 || code[:4] != "XPD-" {
		return ""
	}
	return xpdCategories[code[4]]
}
