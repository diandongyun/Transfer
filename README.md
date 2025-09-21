本开源项目由点动云独家提供技术支持，仅提供交流学习使用，禁止用于违法用途，请各位自行遵守。

# 一键安装
在安装前请确保你的系统支持`bash`环境,且系统网络正常  


# 配置要求  
## 内存  
- 128MB minimal/256MB+ recommend  
## OS  
- Ubuntu 22-24

-FinalShell下载地址 [FinalShell](https://dl.hostbuf.com/finalshell3/finalshell_windows_x64.exe)

# hysteria2中转hysteria2协议

落地机执行
```
bash <(curl -Ls https://raw.githubusercontent.com/Firefly-xui/hysteria2-hysteria2/main/destination-node.sh)
```  
在落地机查找路径为为：/opt/hysteria2_client.yaml的文件将该文件下载，然后上传到中转机的：/opt/路径下。

中转机执行
```
bash <(curl -Ls https://raw.githubusercontent.com/Firefly-xui/hysteria2-hysteria2/main/relay-node.sh)
```  
下载中转机路径为：/opt/hysteria2_relay_client.yaml文件，在v2rayn中导入自定义配置文件即可。


# 落地节点特性

🌟 优势分析：

✅ 性能最大化	不使用混淆、跳端口等特性，减少握手、延迟和处理开销。

✅ 配置简洁易维护	单一端口、无域名，无需证书续签或 CDN 配合。

✅ 稳定性高	配置固定，传输链路稳定，不易出错。

✅ 资源占用少	无额外计算开销，适合低配落地机或 VPS。

✅ 带宽控制防止占满	合理带宽限制防止单用户跑满整个出口。

# 中转节点特性
🌟 优势分析：

✅ 抗审查能力强	使用 SNI 伪装为合法域名，如 Cloudflare、YouTube 等，避开封锁。

✅ 跳跃端口增加隐蔽性	持续变更端口，降低被防火墙静态规则匹配风险。

✅ 混淆规避流量识别	Obfs 层加密流量签名，抗深度包检查（DPI）。

✅ masquerade 提高伪装性	通过伪造 HTTP 代理访问，模拟正常 Web 流量。

✅ TLS 增强安全性	即使中转节点被监听，通信内容依然加密。

✅ 带宽管理，限制带宽，确保最大化服务器宽带性能。

windows客户端
-官方v2rayn [v2rayn](https://github.com/Firefly-xui/hysteria2-hysteria2/releases/download/hysteria2-hysteria2/v2rayN-windows-64.zip)

| 协议组合                            | 抗封锁   | 延迟    | 稳定性   | 部署复杂度 | 适用建议       |
| ------------------------------- | ----- | ----- | ----- | ----- | ---------- |
| hysteria2-hysteria2   | ★★★☆☆ | ★★★★★ | ★★★☆☆ | ★★★★☆ | 稳定直播低延迟低卡顿场景 |
| Hysteria2 + UDP + TLS + Obfs    | ★★★☆☆ | ★★★★★ | ★★★☆☆ | ★★☆☆☆ | 电影流媒体等大流量场景 |
| TUIC + UDP + QUIC + TLS         | ★★★★☆ | ★★★★★ | ★★★★☆ | ★★★★★ | 游戏直播等低延迟场景场景 |
| VLESS + Reality + uTLS + Vision | ★★★★★ | ★★★☆☆ | ★★★★☆ | ★☆☆☆☆ | 安全可靠长期稳定场景     |
