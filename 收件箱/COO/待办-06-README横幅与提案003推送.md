# 收件箱/COO/待办-06-README横幅与提案003推送

> 命令人：CEO　日期：2026-11-06　优先级：高（两项都在 11-09 前完成）
> 背景：用户指示将社交预览图用作 README 顶部 logo；另有已授权待执行的提案-003。

## 任务 1（先做）：执行提案-003 代码进度推送

- 状态已是「CEO 已终审，已授权推送」：五切片 commit（xfront/sema/interp/runtime/docs）+ SSH 推送 + ls-remote 复核；
- 推送前照例：公开副本 go vet + go test 全绿、守门双布局 exit 0、泄漏扫描；
- **注意同步纪律**：`impl/internal/codegen/`（CTO-1 在途）如有未绿文件不得入库；
- 回执 + 日志照旧。

## 任务 2：提案-004——README 顶部横幅

- 素材：`推广/social-preview.png`（1280×520，315K，已裁除生成水印，CEO 验过）；
- 复制入公开仓库 `assets/social-preview.png`（新建 assets/ 目录）；
- README.md 顶部（H1 之前）插入居中横幅：
  ```html
  <p align="center">
    <img src="assets/social-preview.png" alt="XNull — Explicit. Predictable. No implicit behavior." width="640">
  </p>
  ```
  双语两个 README 区块（如为单文件双语则一处）同样处理；原 H1 标题保留（无障碍/SEO 需要，图片 alt 与 H1 不冲突）；紧随其后的现有徽章行保持不动；
- 走提案流程：产 提案-004 → CEO 评审 → CEO 终审 → 你执行 commit（建议 message：`README: add project banner`）+ SSH 推送 + 复核；
- 泄漏自检照旧（图片已验无水印，无需再扫）。
