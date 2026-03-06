// ============================================================================
// 文件名: async_fifo.v
// 描述:   异步FIFO完整RTL实现
//
// 架构图:
//   写时钟域                         读时钟域
//   [write_ctrl]--wptr_gray--[sync_w2r]--wptr_gray_sync--[read_ctrl]
//   [write_ctrl]<-rptr_gray_sync--[sync_r2w]<--rptr_gray--[read_ctrl]
//                    [fifo_mem] (双端口存储器)
//
// 参数: DATA_WIDTH=8, ADDR_WIDTH=4 (深度=16)
// 版本: v1.0
// ============================================================================
`timescale 1ns/1ps

module async_fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
) (
    input  wire                  wclk,   // 写时钟
    input  wire                  wrst_n, // 写复位（低有效）
    input  wire                  winc,   // 写使能
    input  wire [DATA_WIDTH-1:0] wdata,  // 写数据
    output wire                  wfull,  // FIFO满

    input  wire                  rclk,   // 读时钟
    input  wire                  rrst_n, // 读复位（低有效）
    input  wire                  rinc,   // 读使能
    output wire [DATA_WIDTH-1:0] rdata,  // 读数据
    output wire                  rempty  // FIFO空
);

    wire [ADDR_WIDTH:0]   wptr, rptr;
    wire [ADDR_WIDTH:0]   wptr_gray, rptr_gray;
    wire [ADDR_WIDTH:0]   wptr_gray_sync, rptr_gray_sync;
    wire [ADDR_WIDTH-1:0] waddr, raddr;

    fifo_mem    #(.DATA_WIDTH(DATA_WIDTH),.ADDR_WIDTH(ADDR_WIDTH))
        u_mem   (.wclk(wclk),.wenc(winc&~wfull),.waddr(waddr),.wdata(wdata),.raddr(raddr),.rdata(rdata));

    write_ctrl  #(.ADDR_WIDTH(ADDR_WIDTH))
        u_wctrl (.wclk(wclk),.wrst_n(wrst_n),.winc(winc),.rptr_gray_sync(rptr_gray_sync),
                 .wptr(wptr),.wptr_gray(wptr_gray),.waddr(waddr),.wfull(wfull));

    read_ctrl   #(.ADDR_WIDTH(ADDR_WIDTH))
        u_rctrl (.rclk(rclk),.rrst_n(rrst_n),.rinc(rinc),.wptr_gray_sync(wptr_gray_sync),
                 .rptr(rptr),.rptr_gray(rptr_gray),.raddr(raddr),.rempty(rempty));

    sync_w2r    #(.ADDR_WIDTH(ADDR_WIDTH))
        u_sw2r  (.wptr_gray(wptr_gray),.rclk(rclk),.rrst_n(rrst_n),.wptr_gray_sync(wptr_gray_sync));

    sync_r2w    #(.ADDR_WIDTH(ADDR_WIDTH))
        u_sr2w  (.rptr_gray(rptr_gray),.wclk(wclk),.wrst_n(wrst_n),.rptr_gray_sync(rptr_gray_sync));

endmodule

// ============== 双端口存储器 ==============
module fifo_mem #(parameter DATA_WIDTH=8, parameter ADDR_WIDTH=4) (
    input  wire                  wclk, wenc,
    input  wire [ADDR_WIDTH-1:0] waddr, raddr,
    input  wire [DATA_WIDTH-1:0] wdata,
    output wire [DATA_WIDTH-1:0] rdata
);
    localparam DEPTH = (1<<ADDR_WIDTH);
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    integer i;
    initial for(i=0;i<DEPTH;i=i+1) mem[i]=0;
    always @(posedge wclk) if(wenc) mem[waddr]<=wdata;
    assign rdata = mem[raddr];
endmodule

// ============== 写控制器 ==============
// 负责产生写指针、写地址和wfull信号
// 满条件：写指针格雷码最高两位与同步读指针相反，其余位相同
module write_ctrl #(parameter ADDR_WIDTH=4) (
    input  wire                  wclk, wrst_n, winc,
    input  wire [ADDR_WIDTH:0]   rptr_gray_sync,
    output reg  [ADDR_WIDTH:0]   wptr,
    output wire [ADDR_WIDTH:0]   wptr_gray,
    output wire [ADDR_WIDTH-1:0] waddr,
    output reg                   wfull
);
    wire [ADDR_WIDTH:0] wptr_next      = wptr + (winc & ~wfull);
    wire [ADDR_WIDTH:0] wptr_gray_next = wptr_next ^ (wptr_next>>1);
    wire wfull_next =
        (wptr_gray_next[ADDR_WIDTH]   != rptr_gray_sync[ADDR_WIDTH]  ) &&
        (wptr_gray_next[ADDR_WIDTH-1] != rptr_gray_sync[ADDR_WIDTH-1]) &&
        (wptr_gray_next[ADDR_WIDTH-2:0] == rptr_gray_sync[ADDR_WIDTH-2:0]);

    assign waddr     = wptr[ADDR_WIDTH-1:0];
    assign wptr_gray = wptr ^ (wptr>>1);   // 二进制转格雷码

    always @(posedge wclk or negedge wrst_n)
        if(!wrst_n) {wptr,wfull} <= 0;
        else begin wptr<=wptr_next; wfull<=wfull_next; end
endmodule

// ============== 读控制器 ==============
// 负责产生读指针、读地址和rempty信号
// 空条件：读指针格雷码 == 同步写指针格雷码
module read_ctrl #(parameter ADDR_WIDTH=4) (
    input  wire                  rclk, rrst_n, rinc,
    input  wire [ADDR_WIDTH:0]   wptr_gray_sync,
    output reg  [ADDR_WIDTH:0]   rptr,
    output wire [ADDR_WIDTH:0]   rptr_gray,
    output wire [ADDR_WIDTH-1:0] raddr,
    output reg                   rempty
);
    wire [ADDR_WIDTH:0] rptr_next      = rptr + (rinc & ~rempty);
    wire [ADDR_WIDTH:0] rptr_gray_next = rptr_next ^ (rptr_next>>1);
    wire rempty_next = (rptr_gray_next == wptr_gray_sync);

    assign raddr     = rptr[ADDR_WIDTH-1:0];
    assign rptr_gray = rptr ^ (rptr>>1);

    always @(posedge rclk or negedge rrst_n)
        if(!rrst_n) {rptr,rempty} <= {0,1'b1};
        else begin rptr<=rptr_next; rempty<=rempty_next; end
endmodule

// ============== 写→读同步器（2FF） ==============
// 将写指针格雷码从写时钟域同步到读时钟域，消除亚稳态
module sync_w2r #(parameter ADDR_WIDTH=4) (
    input  wire [ADDR_WIDTH:0] wptr_gray,
    input  wire                rclk, rrst_n,
    output reg  [ADDR_WIDTH:0] wptr_gray_sync
);
    reg [ADDR_WIDTH:0] ff1;
    always @(posedge rclk or negedge rrst_n)
        if(!rrst_n) {ff1,wptr_gray_sync}<=0;
        else begin ff1<=wptr_gray; wptr_gray_sync<=ff1; end
endmodule

// ============== 读→写同步器（2FF） ==============
// 将读指针格雷码从读时钟域同步到写时钟域
module sync_r2w #(parameter ADDR_WIDTH=4) (
    input  wire [ADDR_WIDTH:0] rptr_gray,
    input  wire                wclk, wrst_n,
    output reg  [ADDR_WIDTH:0] rptr_gray_sync
);
    reg [ADDR_WIDTH:0] ff1;
    always @(posedge wclk or negedge wrst_n)
        if(!wrst_n) {ff1,rptr_gray_sync}<=0;
        else begin ff1<=rptr_gray; rptr_gray_sync<=ff1; end
endmodule
