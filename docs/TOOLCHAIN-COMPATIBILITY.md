# 工具链兼容验证（2026-11-11）

按 MoonBit 开源大赛组委会统一维护提醒，使用官方当前发布工具链重新验证。

## 实际工具链（`moon version --all`）

```
moon     0.1.20261104 (940aa18 2026-11-04)
moonc    v0.10.20+65efd5b93 (2026-11-05)
moonrun  0.1.20261104 (940aa18 2026-11-04)
```

CI 固定版本：`0.10.20+65efd5b93`（`ci.yml`、`release.yml`，含 Linux/Windows 归档 SHA-256 校验），常量由 `scripts/validate_workflows.py` 双处校验。

## 标准入口验证结果

| 项目 | 结果 |
|---|---|
| `moon check` | 0 errors（62 warnings） |
| `moon build` | 通过 |
| `moon test --target native` | 194/194 |
| `moon test --target js` | 157/157 |
| `moon test --target wasm-gc` | 157/157 |
| `moon run cmd/moonhostabi --target native -- --version` | `moonhostabi 0.6.1` |
| `scripts/verify-package-consumer.py` | `MOONHOSTABI_PACKAGE_CONSUMER_STATUS=GO` |
| `scripts/test_package_consumer.py` | 19/19 |

CI 的 Spike 在 Linux / Windows 双平台执行完整验证，覆盖 native / js / wasm-gc 三目标。

## 适配记录

- Wasm fixtures 用 0.10.20 重新生成：`fixtures/artifacts/*.wasm` 与 `fixtures/oracle/*.wat` 的 `processed-by` 版本更新，`scripts/verify-spike.ps1` 的期望哈希、`docs/report-schema.md` 的机器校验示例同步更新；`abiSha256` 保持不变。
- 语法迁移改到了 vendored 的 `src/internal/wasm_parser/state.mbt`，`third_party/wasm_core_parser/provenance.json` 中该文件的 `vendored_sha256` 与修改说明同步更新，`scripts/verify-vendored-parser.py` 返回 `VENDORED_PARSER_PROVENANCE=GO`。
- 修正测试隔离缺陷：`cleanup_generation_test_directory` 现在也清理 `notes.txt`。此前若中途断言失败留下该文件，目录删不掉，后续每次运行都会在第 707 行报出假失败，掩盖真实原因。产品侧 `cleanup_owned_generation_directory` 拒绝删除未知文件的语义不变。
- 迁移 63 处 `} derive(...)` 旧语法为 `#derive(...)` 前缀形式。CI 对 wasm / js / wasm-gc 库目标使用 `--deny-warn`，会把 `deprecated_syntax` 警告升级为错误，因此这一步是必须的语法适配，而不只是重装工具链。迁移后 `moon fmt --check`、三目标 `--deny-warn` 检查与测试全部通过。

## 平台限制

完整 `scripts/verify-spike.ps1` 需要 PowerShell 7 与 `wasm-tools 1.258.0`（CI 已提供）；本机仅有 PowerShell 5.1，因此 fixture 重建使用 `-KeepBuild`，完整 Spike 由 CI 执行。
