好的 👍 我帮你把内容做成“梅花布局”（即左右交错分布，视觉更活泼，模块间错落有致），排版时用 **Markdown + 表格/分隔** 来模拟。下面是重新排版后的 `README.md` 内容：

````markdown
<marquee style="color:red; font-size:20px; font-weight:bold;">
本开源项目由点动云独家提供技术支持，仅供交流学习使用，禁止用于违法用途，请各位自行遵守。
</marquee>

---

# 🚀 一键安装
> 在安装前请确保你的系统支持 `bash` 环境，且系统网络正常。

---

# ⚙️ 配置要求  
| 资源  | 要求 |
| ----- | ---- |
| 内存  | 128MB minimal / 256MB+ recommend |
| 系统  | Ubuntu 22 - 24 |

📥 FinalShell 下载地址 👉 [FinalShell](https://dl.hostbuf.com/finalshell3/finalshell_windows_x64.exe)

---



### 🌸 hysteria2 中转 hysteria2
**落地机执行**
```bash
bash <(curl -Ls https://raw.githubusercontent.com/diandongyun/Transfer/blob/main/hysteria2-hysteria2/destination-node.sh)
````

在落地机找到：`/opt/hysteria2_client.yaml`上传至中转机的：`/opt/`

**中转机执行**

```bash
bash <(curl -Ls https://raw.githubusercontent.com/diandongyun/Transfer/blob/main/hysteria2-hysteria2/relay-node.sh)
```

在中转机找到：`/opt/hysteria2_relay_client.yaml`
导入 v2rayN 配置即可。


### 🌸 socks5 中转 TUIC

**落地机执行**

```bash
bash <(curl -Ls https://raw.githubusercontent.com/diandongyun/Transfer/blob/main/socks5-TUIC/socks5.sh)
```

找到：`socks5_config.json`上传至中转机的：`/opt/`

**中转机执行**

```bash
bash <(curl -Ls https://raw.githubusercontent.com/diandongyun/Transfer/blob/main/socks5-TUIC/TUIC.sh)
```

导入 v2rayN 配置即可。



### 🌸 socks5 中转 vless

**落地机执行**

```bash
bash <(curl -Ls https://raw.githubusercontent.com/diandongyun/Transfer/blob/main/socks5-vless/socks5.sh)
```

找到：`socks5_config.json`上传至中转机的：`/opt/`

**中转机执行**

```bash
bash <(curl -Ls https://raw.githubusercontent.com/diandongyun/Transfer/blob/main/socks5-vless/vless.sh)
```

导入 v2rayN 配置即可。


### 🌸 vless 中转 socks5

**落地机执行**

```bash
bash <(curl -Ls https://raw.githubusercontent.com/diandongyun/Transfer/blob/main/vless-socks5/vless.sh)
```

找到 `/opt/` 下的 vless 配置文件上传至中转机的：`/opt/`

**中转机执行**

```bash
bash <(curl -Ls https://raw.githubusercontent.com/diandongyun/Transfer/blob/main/vless-socks5/socks5.sh)
```

导入 v2rayN 配置即可。


---

# 🖥️ 落地节点特性

✅ 性能最大化 — 无混淆/跳端口，延迟低
✅ 配置简洁 — 单端口，无证书续签
✅ 稳定性高 — 固定链路，不易出错
✅ 资源占用少 — 低配 VPS 也能跑
✅ 带宽控制 — 防止单用户独占

---

# 🌉 中转节点特性

✅ 抗审查 — SNI 伪装，避开封锁
✅ 隐蔽性 — 跳端口，降低被封风险
✅ 混淆流量 — 抗 DPI 深度检测
✅ masquerade — 伪装为正常 Web 流量
✅ TLS 加密 — 提升通信安全
✅ 带宽管理 — 合理分配，稳定输出

---

# 💻 Windows 客户端

📥 官方 v2rayN 下载
👉 [v2rayN](https://github.com/Firefly-xui/hysteria2-hysteria2/releases/download/hysteria2-hysteria2/v2rayN-windows-64.zip)

---

# 📊 协议性能对比表

| 协议组合                            | 抗封锁   | 延迟    | 稳定性   | 部署复杂度 | 适用建议        |
| ------------------------------- | ----- | ----- | ----- | ----- | ----------- |
| hysteria2 → hysteria2           | ★★★☆☆ | ★★★★★ | ★★★☆☆ | ★★★★☆ | 稳定直播、低延迟场景  |
| socks5 → TUIC (QUIC + TLS)      | ★★★★☆ | ★★★★★ | ★★★★☆ | ★★★★★ | 游戏直播、低延迟场景  |
| socks5 → VLESS (Reality+Vision) | ★★★★★ | ★★★☆☆ | ★★★★☆ | ★★☆☆☆ | 安全可靠、长期稳定场景 |
| vless → socks5 (uTLS+Vision)    | ★★★★☆ | ★★★★☆ | ★★★★☆ | ★★☆☆☆ | 多跳中转、隐蔽性强场景 |

---

📌 若需技术支持或反馈问题，请在仓库 Issues 中提问，或联系维护人（点动云）QQ：1531116771。

⚠️ **最后提醒：本开源项目仅供交流学习，禁止用于违法用途！**


