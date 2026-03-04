// ============================================================================
// 文件名: fifo_normal_test.sv
// 描述:   正常功能测试
// 场景:   先写8个数据，再读8个数据，验证数据顺序正确性
// ============================================================================

`include "fifo_base_test.sv"

class fifo_normal_test #(parameter DATA_WIDTH = 8, parameter ADDR_WIDTH = 4)
    extends fifo_base_test #(DATA_WIDTH, ADDR_WIDTH);

    function new(string name,
                 virtual fifo_write_if #(DATA_WIDTH) w_vif,
                 virtual fifo_read_if  #(DATA_WIDTH) r_vif);
        super.new(name, w_vif, r_vif);
    endfunction

    virtual task run_sequences();
        fifo_write_seq #(DATA_WIDTH) wr_seq;
        fifo_read_seq  #(DATA_WIDTH) rd_seq;

        $display("[%s] Normal Test: write 8, then read 8", name);

        wr_seq = new("wr_seq", env.wr_drv_mbx, 8);
        rd_seq = new("rd_seq", env.rd_drv_mbx, 8);

        wr_seq.run();
        #500;         // 等待数据稳定到读时钟域
        rd_seq.run();
    endtask

endclass : fifo_normal_test
