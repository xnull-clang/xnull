# MEM-09 / S3-06：BLOCKED(B3)

- 任务 env external root 绑定/解除依赖 B3 调度器与任务 env 生命周期。
- 运行时已有 `xrt_task_root_bind/unbind` ABI（impl/runtime/xrt.h:67-68、xrt_abi.c:77-79），但无任务 env 驱动/安全点调度。
- 按任务口径：MEM-09/S3-06 标 BLOCKED(B3)，不算 FAIL。
