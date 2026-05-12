# 快速开始 - 最小可用性配置

本教程将指导您用最简单的方式配置 Xboard-Mihomo 客户端，只需要两步即可完成！

##  最小配置步骤

### 第一步：修改并托管 `remote.config.example.json`

**当前版本的最小可用配置，只需要一个面板地址。**

> ℹ️ **提示**：项目中的 `assets/config/remote.config.example.json` 是完整配置示例。对于最小配置，请参考下方简化示例，删除不需要的字段。

```json
{
  "panelType": "xboard",
  "panels": {
    "mihomo": [
      {
        "url": "https://your-panel.com",
        "description": "主站"
      }
    ]
  }
}
```

**说明：**
- `remote_config.sources`: 配置源会同时获取；谁先成功解密/解析就使用谁；不需要 `priority`。
- `panelType`: 面板类型，支持 `xboard` 和 `v2board`。
- `panels.mihomo`: 面板列表。`mihomo` 是提供商名称，**必须与本地配置文件 `xboard.config.yaml` 中的 provider 字段完全一致**。
- `url`: 这里建议直接填写你当前对接的官网/面板域名。当前客服入口会直接打开这个官网页面，因此如果官网本身已集成 Chatway，就不需要再额外配置 `onlineSupport`。
- `proxy` / `ws` / `update` / `onlineSupport` / `subscription`: 都不是最小打包必填项，可后续再补。

---

### 第二步：配置客户端 `xboard.config.yaml`

1. 复制示例配置文件：`cp assets/config/xboard.config.example.yaml assets/config/xboard.config.yaml`
2. 编辑 `assets/config/xboard.config.yaml`，**只需配置主源地址**：

```yaml
xboard:
  provider: mihomo

  remote_config:
    sources:
      - name: redirect
        url: https://your-domain.com/config.json

  app:
    title: Orange
    website: your-domain.com

  subscription:
    prefer_encrypt: false
```

**说明：**
- `provider`: 必须与 `config.json` 中的 `panels` 键名一致。
- `remote_config.sources[0].url`: 指向你托管的 `config.json` 文件地址。
- `app.title` / `app.website`: 建议填写，不是强制，但会影响应用内展示。
- `subscription.prefer_encrypt`: 最小可用配置下建议先设为 `false`，等你后面补齐订阅域名和解密配置后再开启加密订阅。

> 💡 **多站点切换**：如果你有多个站点，可以在远程配置的 `panels` 中添加多个 provider，然后只需修改本地 `xboard.config.yaml` 中的 `provider` 即可切换。

## 🎯 工作原理

```
客户端启动 → 读取 xboard.config.yaml → 获取主源地址 → 下载 config.json → 解析面板地址 → 连接服务器
```

## ❓ 常见问题

**Q: config.json 必须放在哪里？**
A: 必须托管在一个可访问的 HTTP/HTTPS 地址上（如 GitHub/CDN Raw 地址、自己的服务器或 CDN）。

**Q: 现在最小配置还需要填 onlineSupport 吗？**
A: 不需要。当前代码中的在线客服已经改成直接打开官网页面。如果官网本身已经集成 Chatway，小组件会自动显示。

**Q: provider 名称能自定义吗？**
A: 可以，但必须保持一致：`config.json` 中的 `"panels": { "your_name": [...] }` 必须对应 `xboard.config.yaml` 中的 `provider: your_name`。


