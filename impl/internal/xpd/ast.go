package xpd

// ValueKind 是值的形态。
type ValueKind int

const (
	// StringValue 是带引号字符串；Text 保存已解转义的正文。
	StringValue ValueKind = iota
	// BareValue 是裸词或标识符形态的值（版本号、路径、`true` 之类）。
	BareValue
	// ListValue 是 `[a, b]` 形态：可能为空列表、单元素列表或两元素列表。
	ListValue
	// RangeValue 是 `[a, b)` / `(a, b]` 形态的版本范围（S9 §3.9，仅 language-version 使用）。
	RangeValue
)

// Value 是字段值或块头参数。
type Value struct {
	Kind   ValueKind
	Text   string  // StringValue / BareValue 的正文
	Elems  []Value // ListValue / RangeValue 的元素
	LoIncl bool    // RangeValue：左界是否闭合（`[` 为真）
	HiIncl bool    // RangeValue：右界是否闭合（`]` 为真）
	Pos    Pos
}

// Raw 返回值的规范文本形式，便于比较与打印。
func (v Value) Raw() string {
	switch v.Kind {
	case StringValue:
		return `"` + v.Text + `"`
	case BareValue:
		return v.Text
	case ListValue:
		out := "["
		for i, e := range v.Elems {
			if i > 0 {
				out += ", "
			}
			out += e.Raw()
		}
		return out + "]"
	case RangeValue:
		lo, hi := "(", ")"
		if v.LoIncl {
			lo = "["
		}
		if v.HiIncl {
			hi = "]"
		}
		out := lo
		for i, e := range v.Elems {
			if i > 0 {
				out += ", "
			}
			out += e.Raw()
		}
		return out + hi
	}
	return ""
}

// Node 是文件内的一个条目（字段或块）。
type Node interface {
	Position() Pos
	nodeName() string
}

// Field 是 `name = value`。
type Field struct {
	Name  string
	Value Value
	Pos   Pos
}

// Block 是 `name [args...] [ { ... } ]`；Leaf 为真表示无体条目（如 `module platform`）。
type Block struct {
	Name     string
	Args     []Value
	Children []Node
	Pos      Pos
	Leaf     bool
}

// File 是一个解析完成的 XPD 文件。
type File struct {
	Path  string
	Items []Node
}

func (f *Field) Position() Pos    { return f.Pos }
func (f *Field) nodeName() string { return f.Name }
func (b *Block) Position() Pos    { return b.Pos }
func (b *Block) nodeName() string { return b.Name }

// Find 返回第一个名称匹配的块；不存在返回 nil。
func (f *File) Find(name string) *Block {
	for _, n := range f.Items {
		if b, ok := n.(*Block); ok && b.Name == name {
			return b
		}
	}
	return nil
}
