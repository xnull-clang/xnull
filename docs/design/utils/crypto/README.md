# `xdk.crypto` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.crypto` |
| 层 | L4 数据/编码（文档分组 `utils/`） |
| 依赖 | `xdk.errors`、`xdk.bytes`、`xdk.text`、`xdk.io`、`xdk.random` |
| 被依赖 | `jwt`、`net.tls`、应用 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |
| 实现状态 | M15.1 子集：`HashAlgorithm`/`Hash`/`Hmac`/`ChecksumAlgorithm`/`Checksum`/`ConstantTime` implemented；已实现 Md5/Sha1/Sha256/Sha512（SHA1/SHA512 依赖现有 FFI，运行时向量异常见剩余）；Cipher/Kdf/Asymmetric planned |

---

## 1. 包定位

通用密码学工具：哈希、HMAC、校验和、KDF、对称加解密、AEAD、非对称密钥/签名/加密、常量时间比较。

覆盖标准算法：

- 国际：SHA-1/2/3、BLAKE2/3、HMAC、PBKDF2、scrypt、Argon2id、HKDF、AES-CBC/CTR/GCM、ChaCha20/Poly1305、RSA-OAEP/PKCS1/PSS、ECDSA P-256/P-384、Ed25519。
- 中国国标/商密：SM3（GB/T 32905）、SM4（GB/T 32907）、SM2（GB/T 32918）、ZUC（GM/T 0001）；SM9（GM/T 0044）X。
- 企业/行业算法：X `CryptoProvider` 扩展点； 不内置私有算法。

不做：TLS/证书链（`net.tls`）、JWT（独立包）、HSM、FIPS 认证、侧信道证明、密钥托管。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 算法显式 | 每个操作指定 algorithm enum；无隐式默认 |
| 密钥不打印 | PrivateKey 不导出明文；错误/日志不含密钥 |
| 安全随机 | 密钥/nonce 用 `xdk.random.SecureRandom` |
| 认证加密 | GCM/ChaCha20Poly1305/SM4-GCM 必须校验 tag |
| 常量时间 | 比较 MAC/密钥用 ConstantTime |
| 无全局 | 无全局 provider/密钥库 |
| 标准边界 | 国标算法显式命名；企业算法 X provider |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `HashAlgorithm` | enum | SHA/BLAKE/SM3 | [`HashAlgorithm.md`](HashAlgorithm.md) |
| `Hash` | class | 摘要/hex/base64 | [`Hash.md`](Hash.md) |
| `Hmac` | class | HMAC 签名/验证 | [`Hmac.md`](Hmac.md) |
| `ChecksumAlgorithm` | enum | CRC/Adler/FNV | [`ChecksumAlgorithm.md`](ChecksumAlgorithm.md) |
| `Checksum` | class | 校验和 | [`Checksum.md`](Checksum.md) |
| `KdfAlgorithm` | enum | PBKDF2/scrypt/Argon2/HKDF/SM3-KDF | [`KdfAlgorithm.md`](KdfAlgorithm.md) |
| `Kdf` | class | 密钥派生 | [`Kdf.md`](Kdf.md) |
| `CipherAlgorithm` | enum | AES/ChaCha/SM4/ZUC | [`CipherAlgorithm.md`](CipherAlgorithm.md) |
| `CipherPadding` | enum | None/PKCS7 | [`CipherPadding.md`](CipherPadding.md) |
| `Cipher` | class | 对称/AEAD 加解密 | [`Cipher.md`](Cipher.md) |
| `AsymmetricAlgorithm` | enum | RSA/ECDSA/Ed25519/SM2 | [`AsymmetricAlgorithm.md`](AsymmetricAlgorithm.md) |
| `SignatureScheme` | enum | RSA/ECDSA/Ed25519/SM2 签名 | [`SignatureScheme.md`](SignatureScheme.md) |
| `PublicKey` | class | 公钥解析/编码 | [`PublicKey.md`](PublicKey.md) |
| `PrivateKey` | class | 私钥句柄/解析 | [`PrivateKey.md`](PrivateKey.md) |
| `KeyPair` | class | 公私钥对 | [`KeyPair.md`](KeyPair.md) |
| `Asymmetric` | class | 生成/加密/签名/验证 | [`Asymmetric.md`](Asymmetric.md) |
| `ConstantTime` | class | 常量时间比较 | [`ConstantTime.md`](ConstantTime.md) |

X：`CryptoProvider`、SM9、X25519/ECDH/KeyAgreement、证书链/OCSP、HSM、后量子（ML-KEM/ML-DSA）。

---

## 4. 顶层函数

无；使用静态类/枚举。

---

## 5. 技术/支撑/依赖

- 技术：摘要、MAC、KDF、块/流/AEAD cipher、非对称 key/sign/encrypt、常量时间。
- 支撑：`crypto*Raw`、`CryptoKeyHandle`、`SecureRandom`。
- 依赖：`errors`、`bytes`、`text`、`io`、`xdk.random`。

---

## 6. 场景

### C1：口令存储

`Kdf.pbkdf2`/`scrypt`/`argon2id` + `ConstantTime.equals`。

### C2：AEAD 消息

`Cipher(Aes256Gcm, key)`；`encrypt(plain, nonce, aad)`；`decrypt`。

### C3：国密

`Hash.digest(Sm3, data)`；`Cipher(Sm4Gcm, key)`；`Asymmetric.generate(Sm2)` + `sign/verify`。

### C4：JWT

JWT 包使用 `Hmac`/`Asymmetric`；不把 JWT 放进 crypto。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| SM9 | X |
| ZUC | 支持 Zuc128/Zuc256 流密码 |
| 企业自定义算法 | `CryptoProvider` X |
| DES/RC4/MD5 | 不推荐；MD5 仅兼容 |
| 后量子 | X |
| HSM/证书 | 不做；TLS 另包 |
| JWT | 独立 `xdk.jwt` |

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Value`、`@Deprecated` |
| 处理器 | 标准 A8 / 编译器内建 |
| 生成物 | `KeyPair` 值语义、弃用诊断；密钥句柄不套 `@Value` |
| 状态 | 无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `KeyPair` | `@Value` | 值语义成员 |
| `PublicKey`/`PrivateKey` | — | 句柄/权限资源，保持显式 class |
| 废弃算法入口 | `@Deprecated` | 迁移警告 |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
