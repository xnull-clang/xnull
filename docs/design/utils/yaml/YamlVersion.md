# `YamlVersion`

| 项 | 值 |
| --- | --- |
| 类型 | `enum YamlVersion` |
| 包 | `xdk.yaml` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

YAML 解析版本：1.1（Spring Boot/SnakeYAML 兼容）与 1.2 core schema。

不做：YAML 1.0、JSON schema 变体、自定义 schema、tag 注册。

---

## 2. 设计逻辑

- `Yaml11`：`yes/no/on/off` 按布尔；支持合并键 `<<`；时间戳/二进制标签可作为标准标签处理。
- `Yaml12`：core schema；`yes/no/on/off` 按字符串；合并键不进入 core schema，但可由 `allowMergeKeys` 显式开启（兼容模式）。
- 版本只影响标量解析和默认标签语义，不改变多文档/锚点机制。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 说明 |
| --- | --- |
| `Yaml11` | YAML 1.1 兼容 |
| `Yaml12` | YAML 1.2 core schema |

不变量：成员固定；默认 `Yaml11`；不提供运行时切换全局版本。

---

## 4. 生命周期

值类型；无 close；无资源。

---

## 5. 构造契约

枚举成员直接使用。

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

无实例方法；名称由诊断/`str` 输出。

---

## 8. 使用的技术

- 简单枚举；
- 版本化标量规则。

---

## 9. 需要的支撑

- 语言：enum。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；可共享；无资源。

---

## 12. 示例与反例

正确：Spring Boot 兼容解析用 `YamlVersion.Yaml11`；严格 YAML 1.2 用 `YamlVersion.Yaml12`。  
反例：期望 `Yaml12` 下 `yes` 是 bool；在同一文档混用两个版本；把版本当 tag 白名单。

---

## 13. 测试/场景义务

两个成员；bool 差异；合并键兼容；默认值；非法/缺失版本处理；诊断名称。

---

## 14. XNull 伪代码

```xnull
enum YamlVersion {
    Yaml11,
    Yaml12,
}
```
