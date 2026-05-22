// =============================================================
//  CLASS: fifo_generator
//  Sinh chuỗi fifo_transaction rồi put vào mailbox gen2drv.
//  KHÔNG truy cập DUT signals — thuần túy tạo stimulus data.
//
//  run_all() (blocking) chạy 5 chuỗi test theo thứ tự:
//    T1  seq_fill_drain(N)      — fill đầy rồi drain
//    T2  seq_overflow(N)        — write vượt DEPTH (chặn bởi DUT)
//    T3  seq_underflow()        — read khi empty (chặn bởi DUT)
//    T4  seq_simultaneous(N)    — đọc+ghi cùng 1 cycle
//    T5  seq_random(M, N)       — constrained-random stress test
//
//  Giao tiếp: gen2drv mailbox (bounded hoặc unbounded đều được)
// =============================================================

class fifo_generator;

    mailbox #(fifo_transaction) gen2drv;
    int total_sent;

    function new(mailbox #(fifo_transaction) mb);
        gen2drv    = mb;
        total_sent = 0;
    endfunction

    // ----------------------------------------------------------
    // Helper nội bộ: đóng gói và gửi 1 txn vào mailbox
    // ----------------------------------------------------------
    local task send_one(logic wr, logic rd, logic [7:0] d);
        fifo_transaction t = new();
        t.wr_en = wr;
        t.rd_en = rd;
        t.din   = d;
        gen2drv.put(t.copy());
        total_sent++;
    endtask

    // N cycle idle — deassert cả 2 enable để để tạo khoảng nghỉ
    local task send_idle(int n = 2);
        repeat (n) send_one(1'b0, 1'b0, 8'h00);
    endtask

    // ----------------------------------------------------------
    // TEST 1: Fill rồi Drain — kiểm tra thứ tự FIFO
    // ----------------------------------------------------------
    task seq_fill_drain(int depth);
        $display("\n[GEN] ── TEST 1: Fill & Drain (N=%0d) ──", depth);
        for (int i = 0; i < depth; i++)
            send_one(1'b1, 1'b0, 8'(i * 2));   // ghi: 0x00, 0x02, ..., 0x1E
        send_idle(2);
        for (int i = 0; i < depth; i++)
            send_one(1'b0, 1'b1, 8'h00);        // đọc: scoreboard so sánh thứ tự
        send_idle(2);
    endtask

    // ----------------------------------------------------------
    // TEST 2: Overflow — write vào FIFO full phải bị chặn
    // ----------------------------------------------------------
    task seq_overflow(int depth);
        $display("\n[GEN] ── TEST 2: Overflow Attempt ──");
        for (int i = 0; i < depth; i++)
            send_one(1'b1, 1'b0, 8'hAA);        // fill đầy
        for (int i = 0; i < 3; i++)
            send_one(1'b1, 1'b0, 8'hFF);        // DUT chặn: full=1 → bị bỏ qua
        send_idle(2);
        for (int i = 0; i < depth; i++)
            send_one(1'b0, 1'b1, 8'h00);        // drain
        send_idle(2);
    endtask

    // ----------------------------------------------------------
    // TEST 3: Underflow — read từ FIFO empty phải bị chặn
    // ----------------------------------------------------------
    task seq_underflow();
        $display("\n[GEN] ── TEST 3: Underflow Attempt ──");
        for (int i = 0; i < 3; i++)
            send_one(1'b0, 1'b1, 8'h00);        // DUT chặn: empty=1 → bị bỏ qua
        send_idle(2);
    endtask

    // ----------------------------------------------------------
    // TEST 4: Simultaneous R/W cùng 1 cycle
    // ----------------------------------------------------------
    task seq_simultaneous(int depth);
        int half = depth / 2;
        $display("\n[GEN] ── TEST 4: Simultaneous R/W (pre_fill=%0d, rw=8) ──", half);
        for (int i = 0; i < half; i++)
            send_one(1'b1, 1'b0, 8'(8'h10 + i));    // pre-fill: 0x10..0x17
        send_idle(2);
        for (int i = 0; i < 8; i++)
            send_one(1'b1, 1'b1, 8'(8'hA0 + i));    // đọc+ghi cùng lúc
        send_idle(2);
        for (int i = 0; i < half; i++)
            send_one(1'b0, 1'b1, 8'h00);             // drain phần còn lại
        send_idle(2);
    endtask

    // ----------------------------------------------------------
    // TEST 5: Constrained Random — stress test
    // ----------------------------------------------------------
    task seq_random(int N, int depth);
        fifo_transaction t = new();
        $display("\n[GEN] ── TEST 5: Constrained Random (%0d txns) ──", N);
        for (int i = 0; i < N; i++) begin
            if (!t.randomize())
                $warning("[GEN] randomize() failed at txn %0d", i);
            gen2drv.put(t.copy());
            total_sent++;
        end
        send_idle(2);
        // Drain tối đa depth reads để xả FIFO còn thừa
        for (int i = 0; i < depth; i++)
            send_one(1'b0, 1'b1, 8'h00);
        send_idle(4);
    endtask

    // ----------------------------------------------------------
    // run_all — gọi tất cả sequences, BLOCKING, trả về khi xong
    // Top-level gọi trong main thread, chờ return rồi mới kết thúc sim
    // ----------------------------------------------------------
    task run_all(int depth = 16, int rand_txns = 300);
        seq_fill_drain(depth);
        seq_overflow(depth);
        seq_underflow();
        seq_simultaneous(depth);
        seq_random(rand_txns, depth);
        $display("\n[GEN] ── All sequences complete. Total sent: %0d ──", total_sent);
    endtask

    function void report();
        $display("[GEN] Total transactions sent: %0d", total_sent);
    endfunction

endclass
