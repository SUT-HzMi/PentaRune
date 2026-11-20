# PowerRune24 BLE GATTS 协议说明

> **适用范围**：本文件描述 PowerRune24 系统中由 **RLogo 主控**实现的 BLE GATT Server 协议，供 `PowerRune24-Operator` 或其他 BLE Central 接入使用。
>
> 当前仓库 `PowerRune24-Armour` 是 ESP-NOW 从设备，**不实现 BLE GATTS Server**；它经 ESP-NOW 接收 RLogo 转发的运行、配置和停止事件。BLE 服务端实现位于同级仓库 `../PowerRune24-RLogo`，客户端参考实现位于 `../PowerRune24-Operator`。

## 1. 角色与连接概览

| 角色 | 实现 | 职责 |
|---|---|---|
| BLE Peripheral / GATT Server | RLogo | 广播、提供配置和运行控制特征值、向客户端发送运行日志通知。 |
| BLE Central / GATT Client | PowerRune Operator | 扫描并连接设备，写入启动/停止命令，订阅运行状态通知。 |
| ESP-NOW 从设备 | Armour、Motor | 由 RLogo 通过 ESP-NOW 协议控制；不直接暴露本 BLE GATT 服务。 |

- 设备 GAP 名称：`PowerRune24`
- 广播类型：可连接广播（`ADV_TYPE_IND`）
- 广播包含的 16-bit 服务 UUID：`0xABF0`
- 实际注册的 GATT 服务：`0x1827` 和 `0x1828`
- ATT MTU 初始值：23 bytes（有效单个特征值负载通常不宜假定超过默认 ATT 负载限制，除非连接后协商了更大 MTU）。

> **兼容性注意**：广播服务 UUID `0xABF0` 与实际的 GATT 服务 UUID 不一致。因此，客户端应优先按设备名 `PowerRune24` 扫描、连接后发现服务，而不应仅依赖广播中的服务 UUID 过滤。

所有 UUID 均为 Bluetooth SIG 16-bit UUID，完整形式为：

```text
0000xxxx-0000-1000-8000-00805f9b34fb
```

例如 `0x2A65` 的完整 UUID 为 `00002a65-0000-1000-8000-00805f9b34fb`。

## 2. GATT 服务总览

| 服务 | 16-bit UUID | 完整 UUID | 用途 |
|---|---:|---|---|
| 系统参数设置服务 | `0x1827` | `00001827-0000-1000-8000-00805f9b34fb` | OTA/Wi-Fi、亮度、PID 和装甲板 ID 重置。 |
| 运行控制服务 | `0x1828` | `00001828-0000-1000-8000-00805f9b34fb` | 启动、停止、解锁、OTA 触发、成绩读取。 |

除特别注明外，配置特征值具有 **Read + Write Without Response + Notify** 属性；控制特征值具有 **Write Without Response + Notify** 属性。协议未定义链路层以外的应用层鉴权或加密字段，因此应仅在受控环境中使用。

## 3. 系统参数设置服务（`0x1827`）

| 名称 | UUID | 访问 | 长度 | 编码 / 写入后的行为 |
|---|---:|---|---:|---|
| OTA URL | `0x2AA6` | R / WNR / N | 最大 100 B | 以 NUL 结尾的 C 字符串；写入后更新主控 OTA 地址并触发配置下发。 |
| Wi-Fi SSID | `0x2AC3` | R / WNR / N | 最大 20 B | 以 NUL 结尾的 C 字符串；写入后更新 SSID 并触发配置下发。 |
| Wi-Fi 密码 | `0x2A3E` | R / WNR / N | 最大 20 B | 以 NUL 结尾的 C 字符串；写入后更新密码并触发配置下发。 |
| 自动 OTA | `0x2AC5` | R / WNR / N | 1 B | `0x00` 为关闭；任意非零值为开启。写入后保存并下发配置。 |
| 装甲板亮度 | `0x2A0D` | R / WNR / N | 1 B | `uint8` 亮度值；更新 Armour 1 配置并仅向该装甲板下发。 |
| 靶臂/边缘亮度比例 | `0x2A01` | R / WNR / N | 1 B | `uint8` 比例值；更新 Armour 1 的 `brightness_proportion_edge` 并仅向该装甲板下发。 |
| RLogo 亮度 | `0x2A9B` | R / WNR / N | 1 B | `uint8` 亮度值；更新并保存 RLogo 本机亮度。固件会向 `0x2AA6` 发送文本通知 `Configuration sent to RLogo device`。 |
| 流水灯/矩阵亮度比例 | `0x2A9C` | R / WNR / N | 1 B | `uint8` 比例值；更新 Armour 1 的 `brightness_proportion_matrix` 并触发配置下发。 |
| 电机 PID | `0x2A66` | R / WNR / N | 24 B | 6 个连续的 `float`：`kp, ki, kd, i_max, d_max, out_max`。目标为 ESP32，实际字节序为 little-endian IEEE-754 单精度浮点。仅向 Motor 下发。 |
| 重置装甲板 ID | `0x2B1F` | WNR / N | 1 B | 写入本身不解析命令值；任何成功写入都会启动装甲板 ID 重置任务。 |

### PID 写入示例

Python / Bleak 可按如下方式构造 PID 负载：

```python
import struct

payload = struct.pack("<6f", kp, ki, kd, i_max, d_max, out_max)
await client.write_gatt_char(
    "00002a66-0000-1000-8000-00805f9b34fb", payload, response=False
)
```

对于 URL、SSID 和密码，建议显式包含结尾 `\x00`，并确保字符串（含结尾符）不超过相应的特征值容量。

## 4. 运行控制服务（`0x1828`）

| 名称 | UUID | 访问 | 长度 | 编码 / 行为 |
|---|---:|---|---:|---|
| RUN（启动与运行通知） | `0x2A65` | WNR / N | 4 B 写入；通知为文本 | 写入四个启动参数；订阅后接收 NUL 结尾 UTF-8 运行日志。 |
| 成绩历史 | `0x2A69` | R | 10 B | 最近 10 条成绩的原始 `uint8` 值。代码未定义时间戳、颜色或模式元数据。 |
| 电机解锁 | `0x2A3B` | WNR / N | 1 B | 写入触发 `unlock_task`；当前代码不检查具体字节值。 |
| STOP | `0x2AC8` | WNR / N | 1 B | 写入触发 `stop_task`；Operator 写入 `0x00`。 |
| OTA 触发 | `0x2A9F` | WNR / N | 1 B | 写入触发 `ota_task`；当前代码不检查具体字节值。 |

### 4.1 RUN 写入负载（`0x2A65`）

RUN 命令严格为 4 bytes：

| 偏移 | 字段 | 类型 | `0` | 非零 / `1` |
|---:|---|---|---|---|
| 0 | `color` | `uint8` | 红方 | 蓝方 |
| 1 | `mode` | `uint8` | 大符模式 | 小符模式 |
| 2 | `loop` | `uint8` / bool | 不循环 | 循环 |
| 3 | `direction` | `uint8` / bool | 顺时针 | 逆时针 |

示例：以红方、大符、循环、顺时针启动：

```text
00 00 01 00
```

Bleak 示例：

```python
await client.write_gatt_char(
    "00002a65-0000-1000-8000-00805f9b34fb",
    bytes([0, 0, 1, 0]),
    response=False,
)
```

> **方向日志注意**：固件的一条调试日志将 `value[3] != 0` 打印为 Clockwise，但实际发出的启动文本、Operator 界面和下发给电机的含义均以本表为准：`0` 为顺时针，`1` 为逆时针。

### 4.2 RUN 通知（`0x2A65`）

客户端应在发送第一条 RUN 命令前订阅该特征值通知。通知内容是 NUL 结尾 UTF-8 文本；客户端可先移除所有 `0x00` 字节再解码。

已在 Operator 中处理的典型消息包括：

```text
PowerRune Start with Color Red, Mode Big, Circulation Enabled, Direction Clockwise.
[Score: 12]PowerRune Activated Successfully
PowerRune Activation Failed
PowerRune Run Complete
```

其中：

- 匹配 `\[Score: \d+\]PowerRune Activated Successfully` 时，方括号内数字为本次成绩；
- `PowerRune Activation Failed` 表示激活失败；
- `PowerRune Run Complete` 表示运行结束。

GATT Server 使用 `esp_ble_gatts_send_indicate(..., false)` 发送这些数据，即未请求 indication 确认；上层客户端应自行处理通知丢失、重复连接和状态同步。

## 5. 推荐客户端交互流程

1. 扫描 BLE 外设，按名称 `PowerRune24` 识别目标设备。
2. 连接后执行 GATT 服务发现，确认 `0x1827` 与 `0x1828` 存在。
3. 订阅 `0x2A65`（RUN）通知。
4. 如需参数整定，向 `0x1827` 的对应特征值写入指定长度和编码的数据。
5. 向 `0x2A65` 写入 4-byte RUN 参数启动运行。
6. 通过 RUN 通知获取运行日志与成绩；需要原始最近成绩时，读取 `0x2A69`。
7. 向 `0x2AC8` 写入 `00` 请求停止。

## 6. 与 Armour 的关系

BLE 命令不会直接发给 Armour。RLogo 接收 BLE 写入后，建立对应 FreeRTOS 任务并通过 ESP-NOW 向装甲板与电机分发事件。当前 Armour 固件在启动时注册了：

- `PRA_HIT_EVENT`：向 RLogo 上报击打事件；
- `PRA_START_EVENT`、`PRA_STOP_EVENT`：由 RLogo 控制运行/停止状态；
- `PRC` 下的 OTA、配置完成和 Beacon 超时相关事件。

Armour 的 ESP-NOW 数据帧使用小端字节序，DATA 帧头为 `0x24DF`，可选 ACK 成功/失败帧头分别为 `0x9439` / `0xF2A6`。该链路属于 BLE 之后的设备内部转发协议，详情见 Armour 的 `main/espnow_protocol.h`。

## 7. 实现依据

| 内容 | 代码位置 |
|---|---|
| BLE 名称、服务 UUID、广播内容和特征值 UUID | `../PowerRune24-RLogo/main/ble_events.h`（约 93–157 行） |
| 特征值长度、属性表和访问权限 | `../PowerRune24-RLogo/main/ble_events.h`（约 355–580 行） |
| BLE 写入到配置/运行任务的分发 | `../PowerRune24-RLogo/main/main.cpp`（约 930–1064 行） |
| RUN 参数解释和运行通知 | `../PowerRune24-RLogo/main/main.cpp`（约 146–190 行） |
| Operator UUID 常量、RUN/STOP 写入和通知解析 | `../PowerRune24-Operator/pr-24-operator.py`（约 28–175 行） |
| Armour 的 ESP-NOW 帧格式 | `main/espnow_protocol.h`（约 41–103 行） |
| Armour 初始化及事件注册 | `main/main.cpp`（约 23–67 行） |

## 8. 已知限制与风险

- Operator 当前未开放 OTA 和参数整定设置页；这些特征值仍由固件注册。
- BLE 广播 UUID 与实际 GATT 服务 UUID 不一致，按广播服务 UUID 过滤可能找不到目标设备。
- URL/SSID/密码写入使用 C 字符串拷贝，客户端应提供 NUL 终止符并避免超过特征值缓冲区。
- 协议未定义应用层命令响应、事务 ID 或访问控制。关键操作（OTA、解锁、ID 重置）应在物理和无线环境均受控时执行。
- BLE 运行方向的某条固件调试输出存在历史性文字错误；请按 4.1 节的字节语义与 Operator 显示执行。
