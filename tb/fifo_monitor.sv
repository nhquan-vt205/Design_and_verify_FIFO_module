// =============================================================
//  CLASS: fifo_result — Gói quan sát từ Monitor gửi Scoreboard
//
//  Hai loại sự kiện:
//    WRITE_EVT : DUT chấp nhận 1 write (wr_en && !full)
//                data = din tại thời điểm đó
//    READ_EVT  : DUT xuất    1 read  (rd_en && !empty)
//                data = dout tại thời điểm đó (combinatorial)
//
//  Lý do tách class riêng:
//    Monitor tạo fifo_result → Scoreboard nhận qua mailbox
//    → Scoreboard không cần biết về DUT signals, chỉ dùng fifo_result
// =============================================================

class fifo_result;

    typedef enum logic {WRITE_EVT = 1'b0, READ_EVT = 1'b1} evt_t;

    evt_t       evt_type;
    logic [7:0] data;      // din (WRITE) hoặc dout (READ)

    function new(evt_t t, logic [7:0] d);
        evt_type = t;
        data     = d;
    endfunction

    function string to_string();
        return $sformatf("[%s] data=0x%02h",
                         (evt_type == WRITE_EVT) ? "WR" : "RD", data);
    endfunction

endclass


// =============================================================
//  CLASS: fifo_monitor
//  Quan sát DUT signals tại mỗi posedge clk — PASSIVE (không drive).
//  Gói kết quả vào fifo_result → gửi qua mailbox mon2sb.
//
//  Nguyên tắc tách trách nhiệm:
//    Monitor : quan sát + forward (không so sánh, không report)
//    Scoreboard: chỉ nhận từ mailbox (không cần biết DUT signals)
//
//  Timing:
//    @(posedge clk) → quan sát wr_en/rd_en/din/dout/full/empty
//    dout là combinatorial (= mem[rd_ptr]) → valid tại posedge ✓
//    wr_en/rd_en là giá trị Driver set ở posedge trước → DUT đã latch ✓
// =============================================================

class fifo_monitor;

    mailbox #(fifo_result) mon2sb;
    int obs_wr_cnt;
    int obs_rd_cnt;

    function new(mailbox #(fifo_result) mb);
        mon2sb     = mb;
        obs_wr_cnt = 0;
        obs_rd_cnt = 0;
    endfunction

    // ----------------------------------------------------------
    // run() — vòng lặp quan sát vô tận
    //   Gọi trong: fork mon.run(...); join_none
    //   ref params: trỏ đến signal của module (chỉ đọc theo convention)
    // ----------------------------------------------------------
    task run(
        ref logic       clk,
        ref logic       rst_n,
        ref logic       wr_en,
        ref logic       rd_en,
        ref logic [7:0] din,
        ref logic [7:0] dout,
        ref logic       full,
        ref logic       empty
    );
        fifo_result res;

        forever begin
            @(posedge clk);  // quan sát sau khi DUT đã latch

            if (rst_n) begin

                // Write hợp lệ: DUT chấp nhận din vào mem
                if (wr_en && !full) begin
                    res = new(fifo_result::WRITE_EVT, din);
                    mon2sb.put(res);
                    obs_wr_cnt++;
                end

                // Read hợp lệ: DUT xuất dout = mem[rd_ptr]
                // (dout là combinatorial → valid ngay tại posedge clk)
                if (rd_en && !empty) begin
                    res = new(fifo_result::READ_EVT, dout);
                    mon2sb.put(res);
                    obs_rd_cnt++;
                end

            end
        end
    endtask

    function void report();
        $display("[MON] Observed — writes: %0d  reads: %0d",
                 obs_wr_cnt, obs_rd_cnt);
    endfunction

endclass
