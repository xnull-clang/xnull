package manifest

import (
	"fmt"

	"xnull.dev/xnull/internal/diag"
	"xnull.dev/xnull/internal/xpd"
)

// S8 §3.2 schema：段落/字段白名单、单次段落不重复、容器条目限制、坐标重复。
const (
	codeUnknownNode   = "XPD-201" // 未知段落/字段
	codeDuplicateNode = "XPD-202" // 段落或字段重复
	codeBadContainer  = "XPD-203" // 容器段落含非法条目
	codeCoordDup      = "XPD-302" // 坐标重复
)

type schema struct {
	anyFields bool
	fields    map[string]bool
	blocks    map[string]blockSpec
	container string  // 非空：只允许该名字的块（可重复）
	item      *schema // container 条目的子 schema
}

type blockSpec struct {
	node       *schema
	repeatable bool
}

func fieldSet(names ...string) map[string]bool {
	m := make(map[string]bool, len(names))
	for _, n := range names {
		m[n] = true
	}
	return m
}

var (
	leafSchema       = &schema{}
	propertiesSchema = &schema{anyFields: true}
	exclusionItem    = leafSchema
	dependenciesNode = &schema{container: "dependency", item: dependencyItem}
	dependencyItem   = &schema{
		fields: fieldSet("version", "scope", "optional"),
		blocks: map[string]blockSpec{
			"exclusions": {node: &schema{container: "exclusion", item: exclusionItem}},
		},
	}
	repositoryItem = &schema{fields: fieldSet("url", "mirrorOf")}
	pluginItem     = &schema{
		fields: fieldSet("phase", "goal"),
		blocks: map[string]blockSpec{"configuration": {node: propertiesSchema}},
	}
	resourceItem = &schema{fields: fieldSet("includes", "excludes")}
	buildSchema  = &schema{
		fields: fieldSet("mode", "warnings", "sourceRoot", "testRoot", "entryFile", "entryPackage"),
		blocks: map[string]blockSpec{
			"resources": {node: &schema{container: "resource", item: resourceItem}},
			"plugins":   {node: &schema{container: "plugin", item: pluginItem}},
		},
	}
	activationSchema = &schema{fields: fieldSet("platform")}
	profileSchema    = &schema{
		// 坐标/继承/模块/仓库在 profile 内属「不可覆盖段」：schema 层放行，
		// 由 §3.8 语义检查报 XPD-309（而不是结构错误 XPD-201）。
		fields: fieldSet("groupId", "artifactId", "version", "packaging"),
		blocks: map[string]blockSpec{
			"activation":    {node: activationSchema},
			"properties":    {node: propertiesSchema},
			"dependencies":  {node: dependenciesNode},
			"build":         {node: buildSchema},
			"configuration": {node: propertiesSchema},
			"parent":        {node: parentSchema},
			"modules":       {node: &schema{container: "module", item: leafSchema}},
			"repositories":  {node: &schema{container: "repository", item: repositoryItem}},
		},
	}
	libraryItem = &schema{fields: fieldSet("kind", "system")}
	linkSchema  = &schema{
		fields: fieldSet("unsafe"),
		blocks: map[string]blockSpec{
			"libraries": {node: &schema{container: "library", item: libraryItem}},
		},
	}
	parentSchema = &schema{fields: fieldSet("groupId", "artifactId", "version", "relativePath")}
	rootSchema   = &schema{
		fields: fieldSet("groupId", "artifactId", "version", "packaging"),
		blocks: map[string]blockSpec{
			"parent":               {node: parentSchema},
			"modules":              {node: &schema{container: "module", item: leafSchema}},
			"properties":           {node: propertiesSchema},
			"dependencyManagement": {node: &schema{blocks: map[string]blockSpec{"dependencies": {node: dependenciesNode}}}},
			"dependencies":         {node: dependenciesNode},
			"repositories":         {node: &schema{container: "repository", item: repositoryItem}},
			"build":                {node: buildSchema},
			"profiles":             {node: &schema{container: "profile", item: profileSchema}},
			"configuration":        {node: propertiesSchema},
			"link":                 {node: linkSchema},
		},
	}
)

// validateSchema 校验单份清单的段落/字段结构（S8 §3.2）。
func validateSchema(path string, f *xpd.File) []diag.Diagnostic {
	var ds []diag.Diagnostic
	var proj *xpd.Block
	for _, n := range f.Items {
		b, ok := n.(*xpd.Block)
		if !ok {
			ds = append(ds, mkDiag(path, n.Position(), codeUnknownNode, "顶层只允许 project 块（S8 §3.2）"))
			continue
		}
		if b.Name != "project" {
			ds = append(ds, mkDiag(path, b.Pos, codeUnknownNode, fmt.Sprintf("未知顶层段落 %q（S8 §3.2）", b.Name)))
			continue
		}
		if proj != nil {
			ds = append(ds, mkDiag(path, b.Pos, codeDuplicateNode, "project 块只能出现一次（S8 §3.2）"))
			continue
		}
		proj = b
	}
	if proj == nil {
		return ds
	}
	ds = append(ds, validateChildren(path, proj.Children, rootSchema)...)
	ds = append(ds, duplicateCoords(path, proj)...)
	return ds
}

func validateChildren(path string, children []xpd.Node, s *schema) []diag.Diagnostic {
	var ds []diag.Diagnostic
	seenFields := map[string]bool{}
	seenBlocks := map[string]bool{}
	for _, n := range children {
		switch node := n.(type) {
		case *xpd.Field:
			if s.container != "" {
				ds = append(ds, mkDiag(path, node.Pos, codeBadContainer,
					fmt.Sprintf("容器段落只允许 %s 条目，不允许字段 %q（S8 §3.2）", s.container, node.Name)))
				continue
			}
			if !s.anyFields && !s.fields[node.Name] {
				ds = append(ds, mkDiag(path, node.Pos, codeUnknownNode, fmt.Sprintf("未知字段 %q（S8 §3.2）", node.Name)))
				continue
			}
			if seenFields[node.Name] {
				ds = append(ds, mkDiag(path, node.Pos, codeDuplicateNode, fmt.Sprintf("字段重复：%q（S8 §3.2）", node.Name)))
			}
			seenFields[node.Name] = true
		case *xpd.Block:
			if s.container != "" {
				if node.Name != s.container {
					ds = append(ds, mkDiag(path, node.Pos, codeBadContainer,
						fmt.Sprintf("容器段落只允许 %s 条目，出现 %q（S8 §3.2）", s.container, node.Name)))
					continue
				}
				ds = append(ds, validateChildren(path, node.Children, s.item)...)
				continue
			}
			spec, ok := s.blocks[node.Name]
			if !ok {
				ds = append(ds, mkDiag(path, node.Pos, codeUnknownNode, fmt.Sprintf("未知段落 %q（S8 §3.2）", node.Name)))
				continue
			}
			if !spec.repeatable && seenBlocks[node.Name] {
				ds = append(ds, mkDiag(path, node.Pos, codeDuplicateNode, fmt.Sprintf("段落重复：%q（S8 §3.2）", node.Name)))
				continue
			}
			seenBlocks[node.Name] = true
			ds = append(ds, validateChildren(path, node.Children, spec.node)...)
		}
	}
	return ds
}

// duplicateCoords 检查 dependencies / dependencyManagement.dependencies 坐标重复（XPD-302）。
func duplicateCoords(path string, proj *xpd.Block) []diag.Diagnostic {
	var ds []diag.Diagnostic
	checkContainer := func(container *xpd.Block) {
		seen := map[string]bool{}
		for _, n := range container.Children {
			dep, ok := n.(*xpd.Block)
			if !ok || dep.Name != "dependency" || len(dep.Args) == 0 {
				continue
			}
			coord := dep.Args[0].Text
			if seen[coord] {
				ds = append(ds, mkDiag(path, dep.Pos, codeCoordDup, fmt.Sprintf("坐标重复：%s（S8 §3.2）", coord)))
			}
			seen[coord] = true
		}
	}
	for _, n := range proj.Children {
		b, ok := n.(*xpd.Block)
		if !ok {
			continue
		}
		switch b.Name {
		case "dependencies":
			checkContainer(b)
		case "dependencyManagement":
			for _, c := range b.Children {
				if d, ok := c.(*xpd.Block); ok && d.Name == "dependencies" {
					checkContainer(d)
				}
			}
		}
	}
	return ds
}

func mkDiag(path string, pos xpd.Pos, code, msg string) diag.Diagnostic {
	return diag.Diagnostic{File: path, Line: pos.Line, Col: pos.Col, Code: code, Message: msg}
}
