// =============================================================
//  FIFO Testbench — Top-level OOP module
//  Kiến thức dùng: class, mailbox, rand, constraint, ref task,
//                  covergroup (module), SVA (module), fork/join_none
//  KHÔNG dùng: virtual interface, clocking block, package, UVM
//
//  ┌─────────────────────────────────────────────────────────────┐
//  │                  KIẾN TRÚC TỔNG QUÁT                        │
//  │                                                             │
//  │  fifo_transaction.sv ─── Stimulus object (rand + constraint)│
//  │  fifo_generator.sv   ─── Sinh txn sequences (T1–T5)        │
//  │  fifo_driver.sv      ─── Drive DUT pins theo clock          │
//  │  fifo_monitor.sv     ─── Quan sát DUT outputs (passive)    │
//  │                          + fifo_result (gói quan sát)       │
//  │  fifo_scoreboard.sv  ─── Reference model + PASS/FAIL check │
//  │  fifo_coverage.sv    ─── Functional coverage (sub-module)  │
//  │  fifo_assertions.sv  ─── SVA assertions (sub-module)       │
//  │                                                             │
//  │  Luồng dữ liệu:                                            │
//  │                                                             │
//  │  ┌───────────┐  gen2drv   ┌──────────┐                     │
//  │  │ Generator │──mailbox──►│  Driver  │──► DUT pins         │
//  │  └───────────┘            └──────────┘         │           │
//  │                                           DUT outputs       │
//  │                                                │            │
//  │  ┌───────────┐  mon2sb   ┌──────────┐         │            │
//  │  │Scoreboard │◄─mailbox──│ Monitor  │◄────────┘            │
//  │  └───────────┘           └──────────┘                      │
//  │                                                             │
//  │  ┌─────────────────┐     ┌──────────────────┐             │
//  │  │ fifo_coverage   │     │ fifo_assertions  │             │
//  │  │  (sub-module)   │     │  (sub-module)    │             │
//  │  └────────┬────────┘     └────────┬─────────┘             │
//  │           └─────── DUT signals ───┘                        │
//  └─────────────────────────────────────────────────────────────┘
//
//  Include / compile order:
//    1. sync_fifo.sv        (RTL - vlog riêng)
//    2. fifo_coverage.sv    (module - vlog riêng)
//    3. fifo_assertions.sv  (module - vlog riêng)
//    4. fifo_tb.sv          (top - vlog riêng, `include 5 class bên dưới)
//       └── `include fifo_transaction.sv
//       └── `include fifo_generator.sv
//       └── `include fifo_driver.sv
//       └── `include fifo_monitor.sv    (+ fifo_result)
//       └── `include fifo_scoreboard.sv
// =============================================================

// Class files được include ở đây theo đúng thứ tự phụ thuộc
`include "fifo_transaction.sv"
`include "fifo_generator.sv"
`include "fifo_driver.sv"
`include "fifo_monitor.sv"      // defines fifo_result + fifo_monitor
`include "fifo_scoreboard.sv"   // uses fifo_result (phải sau monitor)


// =============================================================
//  MODULE: fifo_tb — top-level testbench
// =============================================================
module fifo_tb;

    // ----------------------------------------------------------
    // Parameters (phải khớp với DUT sync_fifo)
    // ----------------------------------------------------------
    localparam DATA_WIDTH = 8;
    localparam DEPTH      = 16;

    // ----------------------------------------------------------
    // DUT signals
    // ----------------------------------------------------------
    logic                  clk;
    logic                  rst_n;
    logic                  wr_en;
    logic                  rd_en;
    logic [DATA_WIDTH-1:0] din;
    logic [DATA_WIDTH-1:0] dout;
    logic                  full;
    logic                  empty;
    logic                  almost_full;
    logic                  almost_empty;

    // ----------------------------------------------------------
    // Clock 100 MHz (chu kỳ 10 ns)
    // ----------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ----------------------------------------------------------
    // DUT instantiation
    // ----------------------------------------------------------
    sync_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (DEPTH)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .wr_en       (wr_en),
        .rd_en       (rd_en),
        .din         (din),
        .dout        (dout),
        .full        (full),
        .empty       (empty),
        .almost_full (almost_full),
        .almost_empty(almost_empty)
    );

    // ----------------------------------------------------------
    // Functional Coverage sub-module
    // Xem chi tiết: fifo_coverage.sv
    // Truy cập coverage: u_cov.cg_inst.get_coverage()
    // ----------------------------------------------------------
    fifo_coverage u_cov (
        .clk         (clk),
        .rst_n       (rst_n),
        .wr_en       (wr_en),
        .rd_en       (rd_en),
        .full        (full),
        .empty       (empty),
        .almost_full (almost_full),
        .almost_empty(almost_empty)
    );

    // ----------------------------------------------------------
    // Assertions sub-module
    // Xem chi tiết: fifo_assertions.sv
    // ----------------------------------------------------------
    fifo_assertions u_assert (
        .clk   (clk),
        .rst_n (rst_n),
        .wr_en (wr_en),
        .rd_en (rd_en),
        .full  (full),
        .empty (empty)
    );

    // ----------------------------------------------------------
    // Mailboxes — kênh giao tiếp giữa các OOP components
    // Dùng typed mailbox (#) để type-safe
    // ----------------------------------------------------------
    mailbox #(fifo_transaction) gen2drv = new();   // Generator → Driver
    mailbox #(fifo_result)      mon2sb  = new();   // Monitor  → Scoreboard

    // ----------------------------------------------------------
    // Instantiate OOP components
    // ----------------------------------------------------------
    fifo_generator  gen = new(gen2drv);
    fifo_driver     drv = new(gen2drv);
    fifo_monitor    mon = new(mon2sb);
    fifo_scoreboard sb  = new(mon2sb);

    // ----------------------------------------------------------
    // Reset task — khởi tạo DUT về trạng thái ban đầu
    // ----------------------------------------------------------
    task do_reset();
        rst_n = 1'b0;
        wr_en = 1'b0;
        rd_en = 1'b0;
        din   = 8'h00;
        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;
        @(posedge clk);
        $display("[RESET] Done — empty=%0b  full=%0b", empty, full);
    endtask

    // ==========================================================
    //  MAIN — simulation flow
    // ==========================================================
    initial begin
        $dumpfile("fifo_tb.vcd");
        $dumpvars(0, fifo_tb);

        // --------------------------------------------------
        // BƯỚC 1: Reset DUT
        // --------------------------------------------------
        do_reset();

        // --------------------------------------------------
        // BƯỚC 2: Khởi động Driver, Monitor, Scoreboard
        //   → Chạy song song như background threads (join_none)
        //   → Các thread này chạy vô tận đến khi disable fork
        // --------------------------------------------------
        fork
            drv.run(clk, rst_n, wr_en, rd_en, din, full, empty);
            mon.run(clk, rst_n, wr_en, rd_en, din, dout, full, empty);
            sb.run();
        join_none

        // --------------------------------------------------
        // BƯỚC 3: Chạy toàn bộ test sequences (BLOCKING)
        //   → Generator gửi txns vào gen2drv mailbox
        //   → Driver đồng thời nhận và drive DUT
        //   → Monitor quan sát và gửi vào mon2sb
        //   → Scoreboard xử lý và kiểm tra
        // --------------------------------------------------
        gen.run_all(DEPTH, 300);

        // --------------------------------------------------
        // BƯỚC 4: Chờ mailboxes xả hết
        //   → Đảm bảo mọi txn đã được Drive và Scoreboard check
        // --------------------------------------------------
        wait (gen2drv.num() == 0);   // Driver đã nhận tất cả txns
        wait (mon2sb.num()  == 0);   // Scoreboard đã xử lý tất cả
        repeat (20) @(posedge clk);  // Settling time cho pipeline

        // --------------------------------------------------
        // BƯỚC 5: Kết thúc background threads
        // --------------------------------------------------
        disable fork;

        // --------------------------------------------------
        // BƯỚC 6: Final reports
        // --------------------------------------------------
        gen.report();
        drv.report();
        mon.report();
        sb.report();

        $display("\n[COV] Functional Coverage = %0.1f%%\n",
                 u_cov.cg_inst.get_coverage());

        $finish;
    end

endmodule
