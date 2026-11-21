# `Os`

| 项 | 值 |
| --- | --- |
| 类型 | `class Os`（静态入口） |
| 包 | `xdk.os.host` |
| 稳定性 | `preview` |
| 依赖 | `OsHost`、`OsProfile`、`OsInfo`、`OsCapability` |

---

## 1. 定位

`xdk.os` 的静态入口：获取当前 OS 宿主、OS 快照、平台画像、能力查询。

不做：全局可变状态、自动初始化/关闭、驱动注册、权限提升。

---

## 2. 设计逻辑

- 所有方法都是静态便捷入口；真正的平台服务由 `OsHost` 提供。
- `host()` 每次返回一个**无全局可变状态**的适配器；实现可返回轻量对象，调用方按需缓存。
- `profile()`/`info()`/`kind()`/`family()` 是快照便捷方法，不持有全局单例。
- `hasCapability` 只查 `OsProfile` 声明，不做运行时探测。
- 无 `shutdown()` 全局钩子；宿主/控制器由调用方关闭。

---

## 3. 表示与不变量

无实例字段。

---

## 4. 生命周期

静态类；无实例；无 close；适配器由调用方管理。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Os()` | 无 | 私有；禁止实例化 | 无 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `host` | 当前 OS 宿主 | 无 | `OsHost` | 无 |
| `profile` | OS 画像 | 无 | `OsProfile` | 无 |
| `info` | OS 快照 | 无 | `OsInfo` | 无 |
| `kind` | OS 类型 | 无 | `OsKind` | 无 |
| `family` | OS 家族 | 无 | `OsFamily` | 无 |
| `hasCapability` | 能力查询 | `OsCapability capability` | `Bool` | null → panic |
| `describe` | 单行摘要 | 无 | `String` | 无 |

说明：

- `host()` 不读取全局配置；适配器直接返回当前进程的 OS 宿主。
- `profile()` 是构建/启动期快照；运行期 OS 不会变。
- `host()` 可能每次返回新对象；不要依赖对象身份。
- 需要长期持有宿主时，调用方负责 `close()`。

---

## 8. 使用的技术

- 静态入口；
- 平台适配器；
- 快照；
- 能力查询。

---

## 9. 需要的支撑

- 语言：class、static、Bool、String；
- 运行时/适配器：`nativeOsHost()`；
- 接口：`OsHost`、`OsProfile`、`OsInfo`、`OsKind`、`OsFamily`、`OsCapability`。

---

## 10. 依赖的特性/接口/类

`OsHost`、`OsProfile`、`OsInfo`、`OsKind`、`OsFamily`、`OsCapability`。

---

## 11. 所有权与并发

静态无状态；`host()` 返回调用方拥有的适配器；可并发调用；无全局资源。
相等：无实例；不适用。

---

## 12. 示例与反例

正确：

```xnull
OsHost host = Os.host()
OsProfile profile = host.profile()
if profile.has(OsCapability.Gpu) {
    Result<List<GpuAdapter>, Error> gpus = host.gpuAdapters(Context.background())
}
```

反例：把 `Os.host()` 当全局单例修改；`Os.hasCapability` 后假设服务一定成功；
不关闭长期宿主；在 core 中调用 `xdk.os`。

---

## 13. 测试/场景义务

`host/profile/info/kind/family` 一致；能力查询；未知 OS；无桌面；WASM/容器；
并发调用；宿主关闭后服务返回 `Unavailable`。

---

## 14. XNull 伪代码

```xnull
class Os {
    private Os() {}

    static OsHost host() {
        return nativeOsHost()
    }

    static OsProfile profile() {
        return self.host().profile()
    }

    static OsInfo info() {
        return self.profile().info()
    }

    static OsKind kind() {
        return self.info().kind()
    }

    static OsFamily family() {
        return self.info().family()
    }

    static Bool hasCapability(OsCapability capability) {
        if capability == null { throw "Os.hasCapability: null" }
        return self.profile().has(capability)
    }

    static String describe() {
        return self.profile().describe()
    }
}
```
