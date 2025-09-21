<table><tr><td>
<h2 align="center" style="color:red;">
🚨 本开源项目由点动云独家提供技术支持，仅供交流学习使用，禁止用于违法用途，请各位自行遵守 🚨
</h2>
</td></tr></table>










# 🚀 一键安装指南
在安装前请确保：
- 系统支持 `bash` 环境
- 系统网络连接正常且稳定

---

## 📦 配置要求  
### 💾 内存  
- **最低**：1512MB  
- **推荐**：1GB

### 🖥 操作系统  
- Ubuntu 22 ~ 24  

🔗 **FinalShell 下载地址**：[点击下载](https://dl.hostbuf.com/finalshell3/finalshell_windows_x64.exe)

---

## 🌐 协议部署说明

### 1️⃣ hysteria2 中转 hysteria2 协议
**落地机执行**  
```bash
bash <(curl -Ls https://raw.githubusercontent.com/diandongyun/Transfer/blob/main/hysteria2-hysteria2/destination-node.sh)
```
📂 在落地机查找 `/opt/hysteria2_client.yaml` 文件，将其下载并上传到中转机 `/opt/` 路径下。

**中转机执行**  
```bash
bash <(curl -Ls https://raw.githubusercontent.com/diandongyun/Transfer/blob/main/hysteria2-hysteria2/relay-node.sh)
```
📂 下载 `/opt/hysteria2_relay_client.yaml` 文件，在 v2rayN 中导入自定义配置文件即可。

---

### 2️⃣ socks5 中转 TUIC 协议
**落地机执行**  
```bash
bash <(curl -Ls https://raw.githubusercontent.com/diandongyun/Transfer/blob/main/socks5-TUIC/socks5.sh)
```
📂 查找 `socks5_config.json` 文件，下载并上传到中转机 `/opt/` 路径下。

**中转机执行**  
```bash
bash <(curl -Ls https://raw.githubusercontent.com/diandongyun/Transfer/blob/main/socks5-TUIC/TUIC.sh)
```
📥 根据节点信息在 v2rayN 中导入自定义配置文件即可。

---

### 3️⃣ socks5 中转 vless 协议
**落地机执行**  
```bash
bash <(curl -Ls https://raw.githubusercontent.com/diandongyun/Transfer/blob/main/socks5-vless/socks5.sh)
```
📂 查找 `socks5_config.json` 文件，下载并上传到中转机 `/opt/` 路径下。

**中转机执行**  
```bash
bash <(curl -Ls https://raw.githubusercontent.com/diandongyun/Transfer/blob/main/socks5-vless/vless.sh)
```
📥 根据节点信息在 v2rayN 中导入自定义配置文件即可。

---

### 4️⃣ vless 中转 socks5 协议
**落地机执行**  
```bash
bash <(curl -Ls https://raw.githubusercontent.com/diandongyun/Transfer/blob/main/vless-socks5/vless.sh)
```
📂 查找 `/opt` 文件夹下的 vless JSON 配置文件，下载并上传到中转机 `/opt/` 路径下。

**中转机执行**  
```bash
bash <(curl -Ls https://raw.githubusercontent.com/diandongyun/Transfer/blob/main/vless-socks5/socks5.sh)
```
📥 根据节点信息在 v2rayN 中导入自定义配置文件即可。

---

## 🖥 落地节点特性
🌟 **优势分析**  
- ✅ **性能最大化**：无混淆、无跳端口，减少握手延迟与处理开销  
- ✅ **配置简洁**：单端口、无域名，无需证书续签或 CDN  
- ✅ **稳定性高**：固定配置，链路稳定  
- ✅ **资源占用低**：适合低配 VPS  
- ✅ **带宽控制**：防止单用户占满出口  

---

## 🛰 中转节点特性
🌟 **优势分析**  
- ✅ **抗审查强**：SNI 伪装为合法域名（Cloudflare、YouTube 等）  
- ✅ **跳端口隐蔽**：动态端口降低封锁风险  
- ✅ **混淆防 DPI**：Obfs 加密流量签名  
- ✅ **Masquerade 伪装**：模拟正常 Web 流量  
- ✅ **TLS 安全性高**：即使被监听，通信内容依然加密  
- ✅ **带宽管理**：合理分配，最大化性能  

---

## 💻 Windows 客户端
🔗 官方 v2rayN 下载：[点击下载](https://github.com/Firefly-xui/hysteria2-hysteria2/releases/download/hysteria2-hysteria2/v2rayN-windows-64.zip)

---

## 📊 节点性能与协议组合分析

| 协议组合                              | 抗封锁   | 延迟    | 稳定性   | 部署复杂度 | 适用建议                     |
| ------------------------------------- | ------- | ------- | ------- | --------- | ---------------------------- |
| **hysteria2-hysteria2**               | ★★★☆☆   | ★★★★★   | ★★★☆☆   | ★★★★☆     | 稳定直播、低延迟、低卡顿场景 |
| **socks5-TUIC (UDP+QUIC+TLS)**        | ★★★★☆   | ★★★★★   | ★★★★☆   | ★★★★★     | 游戏、直播等低延迟场景       |
| **socks5-vless (Reality+uTLS+Vision)**| ★★★★★   | ★★★☆☆   | ★★★★☆   | ★★☆☆☆     | 高安全性、长期稳定场景       |
| **vless-socks5 (Reality+uTLS+Vision)**| ★★★★★   | ★★★☆☆   | ★★★★☆   | ★★☆☆☆     | 高安全性、跨平台兼容场景     |

---

## 📌 使用建议
- **新手推荐**：`hysteria2-hysteria2`，部署简单，延迟低  
- **高安全性需求**：`socks5-vless` 或 `vless-socks5`  
- **低延迟高并发**：`socks5-TUIC`  

---

📌 若需技术支持或反馈问题，请在仓库 Issues 中提问，或联系维护人（点动云）QQ：1531116771。

⚠️ **最后提醒：本开源项目仅供交流学习，禁止用于违法用途！**


