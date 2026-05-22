// =============================================================
//  Synchronous FIFO - DUT
//  Parameters : DATA_WIDTH, DEPTH (must be power of 2)
//  Features   : full, empty, almost_full, almost_empty flags
// =============================================================
module sync_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 16
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  wr_en,
    input  logic                  rd_en,
    input  logic [DATA_WIDTH-1:0] din,
    output logic [DATA_WIDTH-1:0] dout,
    output logic                  full,
    output logic                  empty,
    output logic                  almost_full,   // count >= DEPTH-2
    output logic                  almost_empty   // count <= 2
);

    localparam PTR_WIDTH = $clog2(DEPTH);

    // Memory array
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Pointers & count
    logic [PTR_WIDTH-1:0] wr_ptr, rd_ptr;
    logic [PTR_WIDTH  :0] count;   // one extra bit to distinguish full vs empty

    // -------------------------------------------------------
    // Write / Read logic
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;
        end else begin
            // Simultaneous read & write
            if (wr_en && !full && rd_en && !empty) begin
                mem[wr_ptr] <= din;
                wr_ptr      <= wr_ptr + 1;
                rd_ptr      <= rd_ptr + 1;
                // count stays the same
            end
            // Write only
            else if (wr_en && !full) begin
                mem[wr_ptr] <= din;
                wr_ptr      <= wr_ptr + 1;
                count       <= count + 1;
            end
            // Read only
            else if (rd_en && !empty) begin
                rd_ptr <= rd_ptr + 1;
                count  <= count - 1;
            end
        end
    end

    // -------------------------------------------------------
    // Outputs
    // -------------------------------------------------------
    assign dout         = mem[rd_ptr];           // combinatorial read
    assign full         = (count == DEPTH);
    assign empty        = (count == 0);
    assign almost_full  = (count >= DEPTH - 2);
    assign almost_empty = (count <= 2) && !empty;

endmodule
