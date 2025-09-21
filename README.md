<p align="center">
  <marquee behavior="scroll" direction="left" scrollamount="6" style="color:red; font-size:20px; font-weight:bold;">
    ⚠️ 本开源项目由点动云独家提供技术支持，仅供交流学习使用，禁止用于违法用途，请各位自行遵守 ⚠️
  </marquee>
</p>

# 📦 一键安装

在安装前请确保你的系统支持 `bash` 环境，且系统网络正常。

## ✅ 配置要求

- 内存：128MB（最低） / 256MB+（推荐）
- 系统：Ubuntu 22 ~ 24
- FinalShell 下载地址：[FinalShell](https://dl.hostbuf.com/finalshell3/finalshell_windows_x64.exe)

---

# 🚀 协议部署说明

## hysteria2 中转 hysteria2 协议

- 落地机执行：
```bash
bash <(curl -Ls https://raw.githubusercontent.com/diandongyun/Transfer/blob/main/hysteria2-hysteria2/destination-node.sh)
下载落地机 /opt/hysteria2_client.yaml 文件，上传至中转机 /opt/ 路径。

中转机执行：

bash
bash <(curl -Ls https://raw.githubusercontent.com/diandongyun/Transfer/blob/main/hysteria2-hysteria2/relay-node.sh)
下载中转机 /opt/hysteria2_relay_client.yaml 文件，在 v2rayN 中导入自定义配置。

socks5 中转 TUIC 协议
落地机执行：

bash
bash <(curl -Ls https://raw.githubusercontent.com/Transfer/blob/main/socks5-TUIC/socks5.sh)
下载落地机 socks5_config.json 文件，上传至中转机 /opt/ 路径。

中转机执行：

bash
bash <(curl -Ls https://raw.githubusercontent.com/diandongyun/Transfer/blob/main/socks5-TUIC/TUIC.sh)
根据节点信息在 v2rayN 中导入自定义配置。

socks5 中转 VLESS 协议
落地机执行：

bash
bash <(curl -Ls https://raw.githubusercontent.com/diandongyun/Transfer/blob/main/socks5-vless/socks5.sh)
下载落地机 socks5_config.json 文件，上传至中转机 /opt/ 路径。

中转机执行：

bash
bash <(curl -Ls https://raw.githubusercontent.com/Transfer/blob/main/socks5-vless/vless.sh)
根据节点信息在 v2rayN 中导入自定义配置。

VLESS 中转 socks5 协议
落地机执行：

bash
bash <(curl -Ls https://raw.githubusercontent.com/Transfer/blob/main/vless-socks5/vless.sh)
下载落地机 /opt/ 路径下的 VLESS 配置文件，上传至中转机 /opt/ 路径。

中转机执行：

bash
bash <(curl -Ls https://raw.githubusercontent.com/Transfer/blob/main/vless-socks5/socks5.sh)
根据节点信息在 v2rayN 中导入自定义配置。

🧩 节点特性分析
📍 落地节点优势
✅ 性能最大化：无混淆、无跳端口，握手快、延迟低。

✅ 配置简洁：单端口、无域名、无需证书。

✅ 稳定性高：链路固定，出错率低。

✅ 资源占用少：适合低配 VPS。

✅ 带宽控制：防止单用户占满出口。

🔁 中转节点优势
✅ 抗审查强：SNI 伪装合法域名。

✅ 跳跃端口：动态端口规避封锁。

✅ 混淆加密：Obfs 抗 DPI。

✅ masquerade：模拟正常 HTTP 流量。

✅ TLS 加密：通信内容安全。

✅ 带宽管理：提升整体性能。

🖥️ Windows 客户端推荐
官方 v2rayN 下载地址：v2rayN

📊 协议性能对比表
协议组合	抗封锁	延迟	稳定性	部署复杂度	适用建议
hysteria2-hysteria2	★★★☆☆	★★★★★	★★★☆☆	★★★★☆	稳定直播、低延迟场景
socks5-TUIC (QUIC + TLS)	★★★★☆	★★★★★	★★★★☆	★★★★★	游戏直播、低延迟场景
socks5-VLESS (Reality + Vision)	★★★★★	★★★☆☆	★★★★☆	★★☆☆☆	安全可靠、长期稳定场景
VLESS-socks5 (uTLS + Vision)	★★★★☆	★★★★☆	★★★★☆	★★☆☆☆	多跳中转、隐蔽性强场景
