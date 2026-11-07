// singleton.go：单例运行值（S2 §9）：自动 instance、启动前构造、字段/方法可读。
package interp

import (
	"xnull.dev/xnull/internal/xfront"
)

// registerSingleton 登记单例：合成 ClassDecl 以复用字段/方法/静态成员机制。
func (in *Interp) registerSingleton(d *xfront.SingletonDecl) {
	cls := &xfront.ClassDecl{P: d.P, Name: d.Name, Fields: d.Fields, Methods: d.Methods}
	in.singleCls[d.Name] = cls
	in.singletons[d.Name] = d
	in.singletonOrder = append(in.singletonOrder, d)
	in.registerStaticFields(cls)
	in.classOrder = append(in.classOrder, cls) // 静态字段随其他静态字段一起初始化
}

// initSingletons 在顶层/静态字段初始化后、main 前按声明顺序构造实例（§9.2）。
func (in *Interp) initSingletons() {
	for _, d := range in.singletonOrder {
		cls := in.singleCls[d.Name]
		obj := &objv{cls: cls, fields: map[string]*Value{}, singleName: d.Name}
		for _, f := range cls.Fields {
			key := fieldKey(f)
			obj.order = append(obj.order, key)
			obj.fields[key] = in.zeroOf(f.Type)
		}
		v := &Value{K: vObj, O: obj}
		// 先登记再求值：初始化式可引用前面的单例，自引用由 sema 拒绝。
		in.singletonVals[d.Name] = v
		selfScope := newScope(in.globals)
		selfScope.define("self", v)
		for _, f := range cls.Fields {
			if f.Init != nil {
				obj.fields[fieldKey(f)] = coerceByDecl(f.Type, in.eval(f.Init, selfScope))
			}
		}
	}
}

// singletonMember 解析 `S.instance` / `S.staticField`。
func (in *Interp) singletonMember(d *xfront.SingletonDecl, name string) (*Value, bool) {
	if name == "instance" {
		return in.singletonVals[d.Name], true
	}
	if v, ok := in.findStaticField(in.singleCls[d.Name], name); ok {
		return v, true
	}
	return nil, false
}
