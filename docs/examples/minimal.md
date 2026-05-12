# 最小配置示例

这是最简单的配置方案，适合快速测试和个人使用。

## 配置文件

### config.json
```json
{
  "panelType": "xboard",
  "panels": {
    "mihomo": [
      {
        "url": "https://panel.example.com",
        "description": "主站"
      }
    ]
  }
}
```

### xboard.config.yaml
```yaml
xboard:
  provider: mihomo

  remote_config:
    sources:
      - name: redirect
        url: https://raw.githubusercontent.com/username/repo/main/config.json

  app:
    title: Orange
    website: panel.example.com

  subscription:
    prefer_encrypt: false
```

## 配置说明

- **panelType** - 面板类型（建议 `xboard`）
- **panels.mihomo** - 面板/官网地址（必填）
- **remote_config.sources** - 指向托管的 config.json
- **app.title / app.website** - 建议填写，影响显示
- **subscription.prefer_encrypt** - 最小配置建议先 `false`

## 适用场景

✅ 快速测试  
✅ 个人使用  
✅ 单一服务器环境  
✅ 学习和开发  

## 下一步

配置完成后：
1. 将 `config.json` 上传到 GitHub/CDN
2. 修改 `xboard.config.yaml` 中的 URL 为实际地址
3. 确认 `provider` 与 `panels` 键名一致
4. 运行客户端测试

> 当前版本客服入口会直接打开面板/官网页面。如果你的官网右下角已经接入 Chatway，就不需要额外配置 `onlineSupport`。

