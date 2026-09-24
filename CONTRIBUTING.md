# Contributing

## 提交变更前

- 确保功能符合 `docs/PRODUCT.md` 的当前范围
- 执行 `make format` 与 `make check`，为核心逻辑添加或更新测试
- 打包/资源修改执行 `make package-test`；历史格式修改保留固定旧版本 fixtures
- 版本变更更新 `VERSION` 和 `CHANGELOG.md`，引入依赖后提交 `Package.resolved`
- 不在日志、测试夹具或提交记录中包含真实剪贴板内容
- 对涉及权限、持久化或自动粘贴的变更补充风险说明

## Pull Request

PR 描述应包含：

- 解决的问题
- 实现方法
- 验证方式
- UI 变更截图（如适用）
- 隐私或权限影响（如适用）

## 设计原则

- 优先使用 Apple 原生框架
- 保持模块边界清晰
- 空闲时低能耗
- 所有功能都必须有无权限或失败时的合理降级
- 不复制第三方商标、图标、专有素材或源代码

## 许可证

项目采用 [MIT](LICENSE) 许可证。提交的代码与素材应具有可兼容的授权。
