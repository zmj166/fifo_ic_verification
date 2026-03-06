# ============================================================
# 文件名: questa_wave.do
# 描述:   QuestaSim波形配置脚本
#
# 功能:
#   自动添加关键信号到波形窗口，方便调试
#   在QuestaSim GUI模式下自动执行
# ============================================================

# 设置仿真时间精度
quietly WaveActivateNextPane {} 0

# ---- 顶层信号 ----
add wave -noupdate -divider "===== CLOCKS & RESETS ====="
add wave -noupdate -color Cyan  /fifo_tb_top/wclk
add wave -noupdate -color Cyan  /fifo_tb_top/rclk
add wave -noupdate -color Yellow /fifo_tb_top/write_if/wrst_n
add wave -noupdate -color Yellow /fifo_tb_top/read_if/rrst_n

# ---- 写端口 ----
add wave -noupdate -divider "===== WRITE PORT ====="
add wave -noupdate -color Green  /fifo_tb_top/write_if/winc
add wave -noupdate -color Green  /fifo_tb_top/write_if/wdata -radix hex
add wave -noupdate -color Red    /fifo_tb_top/write_if/wfull

# ---- 读端口 ----
add wave -noupdate -divider "===== READ PORT ====="
add wave -noupdate -color Green  /fifo_tb_top/read_if/rinc
add wave -noupdate -color Green  /fifo_tb_top/read_if/rdata -radix hex
add wave -noupdate -color Red    /fifo_tb_top/read_if/rempty

# ---- 内部指针（用于调试）----
add wave -noupdate -divider "===== INTERNAL POINTERS ====="
add wave -noupdate /fifo_tb_top/dut/u_wctrl/wptr  -radix hex
add wave -noupdate /fifo_tb_top/dut/u_rctrl/rptr  -radix hex
add wave -noupdate /fifo_tb_top/dut/u_wctrl/wptr_gray -radix hex
add wave -noupdate /fifo_tb_top/dut/u_rctrl/rptr_gray -radix hex
add wave -noupdate /fifo_tb_top/dut/wptr_gray_sync -radix hex
add wave -noupdate /fifo_tb_top/dut/rptr_gray_sync -radix hex

# ---- 存储器（展开显示）----
add wave -noupdate -divider "===== MEMORY ====="
add wave -noupdate /fifo_tb_top/dut/u_mem/mem -radix hex

# 设置波形格式
configure wave -namecolwidth 200
configure wave -valuecolwidth 80
configure wave -timelineunits ns

# 运行仿真
run -all

# 缩放到全视图
wave zoom full
