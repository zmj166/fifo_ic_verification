# 异步FIFO IC验证项目

## 项目概述

本项目是一个完整的异步FIFO（Asynchronous First-In First-Out）IC验证项目，
涵盖RTL设计、SystemVerilog验证环境搭建、VCS和QuestaSim工具使用、
波形调试（Verdi）以及功能覆盖率收集的完整流程。

---

## 目录结构

```
async_fifo_verification/
├── rtl/                        # 待测设计（DUT）
│   └── async_fifo.v            # 异步FIFO RTL实现
│
├── tb/                         # 验证平台
│   ├── fifo_tb_top.sv          # TB顶层模块
│   ├── interface/
│   │   └── fifo_if.sv          # 接口定义（write/read interface）
│   ├── env/
│   │   ├── fifo_transaction.sv # 事务类
│   │   ├── fifo_driver.sv      # 驱动器类（Write/Read Driver）
│   │   ├── fifo_monitor.sv     # 监测器类（Write/Read Monitor）
│   │   ├── fifo_scoreboard.sv  # 记分板类
│   │   └── fifo_env.sv         # 验证环境顶层
│   ├── sequence/
│   │   └── fifo_sequence.sv    # 测试序列（多种场景）
│   ├── test/
│   │   ├── fifo_base_test.sv   # 基础测试类
│   │   ├── fifo_normal_test.sv # 正常功能测试
│   │   ├── fifo_full_empty_test.sv # 满空边界测试
│   │   └── fifo_random_test.sv # 随机并发测试
│   └── coverage/
│       └── fifo_coverage.sv    # 功能覆盖率模型
│
├── sim/
│   ├── vcs/
│   │   └── Makefile            # VCS仿真脚本
│   └── questa/
│       ├── Makefile            # QuestaSim仿真脚本
│       └── questa_wave.do      # 波形配置脚本
│
├── scripts/
│   ├── check_env.sh            # 环境检查脚本
│   └── run_all.sh              # 一键回归脚本
│
├── docs/
│   └── README.md               # 本文档
│
└── waves/                      # 波形输出目录
```

---

## 异步FIFO设计原理

### 核心挑战：跨时钟域

异步FIFO的写端和读端工作在两个**完全独立**的时钟域：
- 写时钟（wclk）：控制数据写入
- 读时钟（rclk）：控制数据读出

跨时钟域传递信号时面临**亚稳态**问题：
> 亚稳态：当一个触发器的数据输入在时钟边沿附近切换时，输出可能在0和1之间振荡，
> 最终稳定在一个不确定的值，导致逻辑错误。

### 解决方案：格雷码指针同步

```
写时钟域                    读时钟域
[write_ctrl]                [read_ctrl]
  wptr(bin) → wptr_gray ──[sync_w2r 2FF]──► wptr_gray_sync → 空判断
  满判断 ◄── rptr_gray_sync ──[sync_r2w 2FF]◄── rptr_gray ← rptr(bin)
```

**格雷码的优势**：相邻数值只有1个bit变化，即使在同步过程中发生亚稳态，
也只会让指针偏差一个值（非常小的错误），而不是造成大幅度跳变。

### 满/空判断逻辑

**空判断（rempty）**：
```
rempty = (rptr_gray_next == wptr_gray_sync)
```
读指针追上写指针时，FIFO为空。

**满判断（wfull）**：
```
wfull = (wptr_gray_next[MSB]   != rptr_gray_sync[MSB]  ) &&
        (wptr_gray_next[MSB-1] != rptr_gray_sync[MSB-1]) &&
        (wptr_gray_next[LSBs]  == rptr_gray_sync[LSBs] )
```
写指针比读指针超前了整整一圈（最高两位相反，其余位相同）。

---

## 验证环境架构

```
┌─────────────────────────────────────────────────┐
│                   Test Layer                     │
│  [NormalTest] [FullEmptyTest] [RandomTest]       │
└───────────────────────┬─────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────┐
│               Environment Layer                  │
│                                                  │
│  [WriteSeq]──mbx──►[WriteDriver]──►[DUT Write]  │
│  [ReadSeq] ──mbx──►[ReadDriver] ──►[DUT Read ]  │
│                                                  │
│  [DUT Write]──►[WriteMon]──mbx──►[Scoreboard]   │
│  [DUT Read] ──►[ReadMon] ──mbx──►[Scoreboard]   │
│                                   ↓ PASS/FAIL    │
│                    [Coverage Model]              │
└─────────────────────────────────────────────────┘
```

### 各组件职责

| 组件 | 文件 | 职责 |
|------|------|------|
| Interface | fifo_if.sv | 封装DUT端口，定义时序（clocking block） |
| Transaction | fifo_transaction.sv | 验证数据的基本单元（写/读操作） |
| Driver | fifo_driver.sv | 将Transaction转化为信号驱动到DUT |
| Monitor | fifo_monitor.sv | 被动监测信号，捕获Transaction |
| Scoreboard | fifo_scoreboard.sv | 比较实际输出与预期输出，判断PASS/FAIL |
| Coverage | fifo_coverage.sv | 记录功能覆盖率 |
| Sequence | fifo_sequence.sv | 产生不同场景的测试激励 |
| Test | fifo_*_test.sv | 选择并配置测试场景 |
| Env | fifo_env.sv | 连接所有组件 |
| TB Top | fifo_tb_top.sv | 时钟生成、DUT实例化、断言 |

---

## 环境说明

### 虚拟机配置

本项目基于**预配置的EDA虚拟机镜像**，所有工具已安装完毕，无需手动安装。

| 项目 | 版本/说明 |
|------|-----------|
| 虚拟机软件 | VMware Workstation 16.1.2 |
| 操作系统 | CentOS 7.9，64bit |
| 用户名 | host，密码：linuxserver（root密码相同） |
| VCS | VCS MX 2018.09 |
| Verdi | 2018.09-SP2（波形查看，命令：`verdi`） |
| DVE | VCS内置波形工具（命令：`dve`） |
| QuestaSIM | 10.7c（命令：`vsim`） |
| 内存 | 默认8G（可在VMware中调整） |
| CPU | 默认8核（可在VMware中调整） |

### License说明

**License会在CentOS启动后自动加载**，无需手动配置。

如果License未能自动启动，通常是MAC地址不匹配导致的。解决方法：
1. 关闭虚拟机
2. 在VMware中点击 **编辑虚拟机设置 → 网络适配器 → 高级**
3. 将MAC地址修改为：`00:0C:29:9C:3C:E0`
4. 重新启动虚拟机，License会自动加载

### 常用工具启动命令

| 工具 | 命令 |
|------|------|
| VCS仿真 | `vcs`（参考本项目Makefile） |
| DVE波形 | `dve` |
| Verdi波形 | `verdi` |
| QuestaSIM | `vsim` |

### 与Windows主机传输文件

**方式一：FTP服务器**
```bash
su root               # 切换到root，密码：linuxserver
service vsftpd start  # 启动FTP服务
ifconfig              # 查看IP，例如192.168.1.90
# 在Windows资源管理器中输入：ftp://192.168.1.90
```

**方式二：Samba服务器**
```bash
su root
service smb start
# 在Windows资源管理器中输入：\\192.168.1.90
# 账号密码：host / linuxserver
```

**方式三：VMware共享文件夹**（在VMware设置中配置）

### 环境自检

```bash
cd scripts/
chmod +x check_env.sh
./check_env.sh
```

---

## 使用教程

### Step 1：验证工具安装

```bash
cd scripts/
./check_env.sh
```

期望输出：
```
--- EDA Tools ---
  ✓ VCS (Synopsys): VCS MX vO-2018.09...
  ✓ Verdi (Synopsys): Verdi ...
  ✓ QuestaSim (Mentor): QuestaSim ...
```

---

### Step 2：使用VCS运行单个测试

```bash
cd sim/vcs/

# 运行正常功能测试
make sim TEST=normal

# 运行满空边界测试
make sim TEST=full_empty

# 运行随机并发测试
make sim TEST=random
```

**成功输出示例**：
```
[write_drv] Write data=0x3A
[write_mon] Captured WRITE data=0x3A
[read_mon]  Captured READ  data=0x3A
[SCB] PASS READ data=0x3A (expected=0x3A)
...
╔══════════════════════════════════════╗
║        SCOREBOARD REPORT             ║
╠══════════════════════════════════════╣
║  Total Writes :    8                 ║
║  Total Reads  :    8                 ║
║  PASS         :    8                 ║
║  FAIL         :    0                 ║
║  *** VERIFICATION PASSED ***         ║
╚══════════════════════════════════════╝
```

---

### Step 3：使用Verdi查看波形

```bash
cd sim/vcs/

# 先运行仿真（产生波形文件）
make sim TEST=normal

# 打开Verdi
make verdi
```

**Verdi波形调试技巧**：
1. 在左侧Instance树中展开 `fifo_tb_top` → `dut`
2. 将关键信号（wclk, rclk, winc, wdata, wfull, rinc, rdata, rempty）拖到波形窗口
3. 使用 `Ctrl+F` 搜索信号名
4. 按 `F` 键缩放到全局视图
5. 使用 `Shift+A` 添加所有子模块信号

---

### Step 4：使用QuestaSim运行（GUI模式）

```bash
cd sim/questa/

# GUI模式（可交互查看波形）
make gui TEST=normal

# 批处理模式
make sim TEST=normal
```

**QuestaSim GUI操作**：
1. 在Wave窗口 → Add → By Name 搜索信号
2. 右键信号 → Radix → Hexadecimal 切换显示格式
3. 使用Zoom In/Out调整时间轴

---

### Step 5：运行完整回归测试

```bash
# VCS回归
cd sim/vcs/
make regress

# 或使用脚本
cd scripts/
./run_all.sh vcs      # VCS
./run_all.sh questa   # QuestaSim
```

---

### Step 6：查看代码覆盖率

```bash
cd sim/vcs/

# 运行带覆盖率的仿真
make sim TEST=normal
make sim TEST=full_empty
make sim TEST=random

# 合并覆盖率数据库并生成报告
make cov
```

生成HTML报告：`coverage_report/dashboard.html`

---

### Step 7：添加自定义测试场景

1. 在 `tb/sequence/fifo_sequence.sv` 中添加新的Sequence类
2. 在 `tb/test/` 中创建新的Test类
3. 在 `tb/fifo_tb_top.sv` 中添加对应的编译宏
4. 在Makefile中添加新测试目标

---

## 常见问题排查

### Q1: VCS编译报 "Unknown module" 错误

**原因**：RTL文件路径错误，或 `+incdir` 没有包含所有目录

**解决**：检查Makefile中的 `RTL_FILES` 和 `+incdir` 路径

### Q2: 波形文件为空（FSDB）

**原因**：`$fsdbDumpfile` 需要Verdi license和fsdb PLI库

**解决**：
```bash
# 确认FSDB PLI库路径
export LD_LIBRARY_PATH=$VERDI_HOME/share/PLI/VCS/LINUX64:$LD_LIBRARY_PATH
```

### Q3: Scoreboard显示FAIL

**原因**：写入数据和读出数据不一致，可能原因：
1. 指针同步延迟导致数据读取时机不对
2. 测试中有无效写入（wfull时写入被忽略但scoreboard记录了）

**调试方法**：打开波形，观察 `wptr` 和 `rptr` 的变化，检查数据是否按FIFO顺序出来

### Q4: 工具无法启动 / License错误

虚拟机的License通过MAC地址绑定，自动加载，无需手动配置 `LM_LICENSE_FILE`。

如果出现License错误，按以下步骤处理：
```bash
# 1. 关闭虚拟机
# 2. 在VMware：编辑虚拟机设置 -> 网络适配器 -> 高级
# 3. 确认MAC地址为：00:0C:29:9C:3C:E0（不对则手动填入）
# 4. 重新开机，License自动加载
ifconfig   # 开机后用此命令确认MAC地址是否正确
```

### Q5: 断言失败（Assertion Failure）

断言失败会显示：
```
[ASSERT] rempty should be 1 after reset!
```

**调试**：检查复位逻辑，确认 `rrst_n` 低电平持续足够时间（建议≥4个时钟周期）

---

## 关键验证点

| 验证点 | 测试场景 | 检查方法 |
|--------|----------|----------|
| 正常写读 | normal test | Scoreboard数据比较 |
| FIFO写满 | full_empty test | wfull信号正确置位 |
| FIFO读空 | full_empty test | rempty信号正确置位 |
| 写满时保护 | full_empty test | 写数据不被接受不影响已有数据 |
| 读空时保护 | full_empty test | rempty时rinc无效 |
| 数据完整性 | random test | Scoreboard全程比较 |
| 指针回绕 | random test (64次) | 指针超过2^ADDR_WIDTH |
| 异步时钟 | 所有测试 | 写100MHz读75MHz |
| 复位行为 | 所有测试 | 断言检查 |

---

## 参考资料

1. **Clifford Cummings**: "Simulation and Synthesis Techniques for Asynchronous FIFO Design" (SNUG 2002) - 格雷码异步FIFO最权威的参考论文
2. **Synopsys VCS文档**: 在CentOS中输入 `vcs -help` 查看，或联系镜像提供者获取文档
3. **QuestaSim文档**: 在CentOS中输入 `vsim -help` 查看
4. **Verdi用户手册**: 在CentOS中输入 `verdi -help` 查看

