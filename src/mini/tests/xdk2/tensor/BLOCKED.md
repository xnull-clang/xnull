# xdk.tensor BLOCKED

`mini --sema src/xdk/tensor/Tensor.x --xdk-root src/xdk` fails at the first `TensorShape` comparison:

```text
src/xdk/tensor/Tensor.x:116:28: expected type
```

The parser accepts the class header and constructors but rejects later comparison expressions in this file; no `.x` scenario is registered in `xdk2.sh`. TensorView/TensorOps therefore have no runtime evidence, and B4-01 cannot close.
