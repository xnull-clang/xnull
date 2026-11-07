// bytes.go：Bytes 内建值（S1 §9.7）：fromString/length/get/set/push/append/slice。
package interp

func (in *Interp) callBytesMethod(recv *Value, name string, args []*Value) *Value {
	need := func(k int) {
		if len(args) != k {
			panic(runtimeErr{"Bytes." + name + " 参数个数不符（S1 §9.7）"})
		}
	}
	index := func(v *Value) int {
		if v.K != vInt {
			panic(runtimeErr{"Bytes 下标必须是 Int（S1 §9.7）"})
		}
		return int(v.I)
	}
	switch name {
	case "length":
		need(0)
		return &Value{K: vInt, I: int64(len(recv.Bs))}
	case "get":
		need(1)
		i := index(args[0])
		if i < 0 || i >= len(recv.Bs) {
			panic(fatal{"Bytes.get 下标越界"})
		}
		return &Value{K: vInt, I: int64(recv.Bs[i])}
	case "set":
		need(2)
		i := index(args[0])
		if args[1].K != vInt {
			panic(runtimeErr{"Bytes.set 的值必须是 Int（S1 §9.7）"})
		}
		if i < 0 || i >= len(recv.Bs) {
			panic(fatal{"Bytes.set 下标越界"})
		}
		recv.Bs[i] = byte(args[1].I)
		return &Value{K: vNull}
	case "push":
		need(1)
		if args[0].K != vInt {
			panic(runtimeErr{"Bytes.push 的值必须是 Int（S1 §9.7）"})
		}
		recv.Bs = append(recv.Bs, byte(args[0].I))
		return &Value{K: vNull}
	case "append":
		need(1)
		if args[0].K != vBytes {
			panic(runtimeErr{"Bytes.append 只接受 Bytes（S1 §9.7）"})
		}
		recv.Bs = append(recv.Bs, args[0].Bs...)
		return &Value{K: vNull}
	case "slice":
		need(2)
		start := index(args[0])
		end := index(args[1])
		if start < 0 || end < start || end > len(recv.Bs) {
			panic(fatal{"Bytes.slice 范围非法"})
		}
		out := make([]byte, end-start)
		copy(out, recv.Bs[start:end])
		return &Value{K: vBytes, Bs: out}
	}
	panic(runtimeErr{"Bytes 没有成员方法 " + name + "（S1 §9.7）"})
}
