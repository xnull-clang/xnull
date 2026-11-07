// factory.go：工厂命名空间的静态方法调用（S2 §10；不是类型，无 self/实例）。
package interp

import (
	"fmt"

	"xnull.dev/xnull/internal/xfront"
)

func (in *Interp) findFactoryMethod(fac *xfront.FactoryDecl, name string) []*xfront.MethodDecl {
	var out []*xfront.MethodDecl
	for _, m := range fac.Methods {
		if m.Name == name {
			out = append(out, m)
		}
	}
	return out
}

// callFactoryMethod 执行工厂方法：无 self；`try` 在方法边界转 Result 返回（§10.2）。
func (in *Interp) callFactoryMethod(fac *xfront.FactoryDecl, name string, args []*Value, pos xfront.Pos) (v *Value, err error) {
	cands := in.findFactoryMethod(fac, name)
	if len(cands) == 0 {
		panic(runtimeErr{"工厂 " + fac.Name + " 没有方法 " + name + "（§10.2）"})
	}
	m := in.selectMethod(name, cands, args)
	defer func() {
		if r := recover(); r != nil {
			switch sig := r.(type) {
			case ctrlReturn:
				v, err = sig.v, nil
			case ctrlErr:
				v, err = &Value{K: vResult, R: sig.r}, nil
			case ctrlBreak, ctrlContinue:
				err = fmt.Errorf("break/continue 出现在循环或 switch 之外")
			case runtimeErr, fatal:
				panic(sig)
			default:
				panic(r)
			}
		}
	}()
	prev := in.factoryCtx
	in.factoryCtx = fac
	defer func() { in.factoryCtx = prev }()
	sc := newScope(in.globals)
	for i, prm := range m.Params {
		if i < len(args) {
			sc.defineTyped(prm.Name, prm.Type, args[i])
		} else {
			sc.defineTyped(prm.Name, prm.Type, &Value{K: vNull})
		}
	}
	if m.Body != nil {
		in.execBlock(m.Body, sc)
	}
	return &Value{K: vNull}, nil
}
