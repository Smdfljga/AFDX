// rx_port_buf : interface-only skeleton for Quartus RTL Viewer
// Real parameters/ports + real sub-module instantiations only;
// all procedural logic and loose assign statements have been removed on purpose.
module rx_port_buf #(                                       
    parameter DATA_WIDTH        = 8,        
    parameter VL_INDEX_WIDTH    = 4,        
    parameter BYTE_OFFSET_WIDTH = 11,        
    parameter FRAME_LEN_WIDTH   = 16,       
    parameter FRAME_CNT_WIDTH   = 3         
)(                                                          
    
    input  wire                          clk,                    
    input  wire                          rst_b,                  

    
    input  wire                          wr_en,                  
    input  wire [VL_INDEX_WIDTH-1:0]     wr_vl_index,            
    input  wire [BYTE_OFFSET_WIDTH-1:0]  wr_byte_offset,         
    input  wire [DATA_WIDTH-1:0]         wr_data,                
    input  wire                          wr_frame_done,          
    input  wire [FRAME_LEN_WIDTH-1:0]    wr_frame_len,           
    input  wire                          wr_queue_mode,          
    output wire                          wr_full,                

    
    input  wire                          rd_en,                  
    input  wire [VL_INDEX_WIDTH-1:0]     rd_vl_index,            
    input  wire [BYTE_OFFSET_WIDTH-1:0]  rd_byte_offset,         
    output wire [DATA_WIDTH-1:0]         rd_data,                
    output wire                          rd_valid,               

    
    
    
    output wire [(1<<VL_INDEX_WIDTH)*FRAME_LEN_WIDTH-1:0] rd_frame_len_all,   
    output wire [(1<<VL_INDEX_WIDTH)*(FRAME_CNT_WIDTH+1)-1:0] rd_frame_cnt_all 
);
localparam SLOT_NUM    = 1 << VL_INDEX_WIDTH;               
    localparam MAX_FRAMES  = 1 << FRAME_CNT_WIDTH;              
    localparam SLOT_BYTES  = 1 << BYTE_OFFSET_WIDTH;            
    reg [BYTE_OFFSET_WIDTH-1:0] wr_ptr [0:SLOT_NUM-1];          
    reg [BYTE_OFFSET_WIDTH-1:0] rd_ptr [0:SLOT_NUM-1];          
    reg [FRAME_CNT_WIDTH:0]     frame_cnt [0:SLOT_NUM-1];   
    reg                         queue_mode [0:SLOT_NUM-1];      
    reg [FRAME_CNT_WIDTH-1:0]   fifo_wr_ptr [0:SLOT_NUM-1];  
    reg [FRAME_CNT_WIDTH-1:0]   fifo_rd_ptr [0:SLOT_NUM-1];  
    reg [FRAME_LEN_WIDTH-1:0]   len_fifo [0:SLOT_NUM-1][0:MAX_FRAMES-1];  
    reg [BYTE_OFFSET_WIDTH-1:0] rd_progress [0:SLOT_NUM-1];  
    integer slot_i;                                             
    integer fifo_i;                                             
    wire [BYTE_OFFSET_WIDTH-1:0] wr_offset = wr_queue_mode ?  
        wr_ptr[wr_vl_index] + wr_byte_offset : wr_byte_offset;  
    wire [BYTE_OFFSET_WIDTH-1:0] rd_offset;
    wire [VL_INDEX_WIDTH+BYTE_OFFSET_WIDTH-1:0] wr_addr =   
        {wr_vl_index, wr_offset};                               
    wire [VL_INDEX_WIDTH+BYTE_OFFSET_WIDTH-1:0] rd_addr =   
        {rd_vl_index, rd_offset};                               
    rx_port_buf_ip u_rx_port_buf_ip (                       
        .inclock    (clk),                                      
        .in_aclr    (~rst_b),                                   
        .wraddress  (wr_addr),                                  
        .data       (wr_data),                                  
        .wren       (wr_en && !wr_full),                    
        .outclock   (clk),                                      
        .out_aclr   (~rst_b),                                   
        .rdaddress  (rd_addr),                                  
        .rden       (rd_en),                                    
        .q          (rd_data)                                   
    );                                                      
    reg rd_en_d1;                                               
    reg rd_en_d;                                                
    wire pointers_equal;
    wire [BYTE_OFFSET_WIDTH:0] used_current =               
        (frame_cnt[wr_vl_index] == 0) ? 0 :                 
        pointers_equal ? SLOT_BYTES :                       
        (wr_ptr[wr_vl_index] > rd_ptr[wr_vl_index])         
            ? {1'b0, wr_ptr[wr_vl_index]} - {1'b0, rd_ptr[wr_vl_index]}  
            : SLOT_BYTES -                                  
              ({1'b0, rd_ptr[wr_vl_index]} - {1'b0, wr_ptr[wr_vl_index]}); 
    wire [BYTE_OFFSET_WIDTH:0] free_current;
    wire [FRAME_LEN_WIDTH-1:0] head_len =                   
        len_fifo[rd_vl_index][fifo_rd_ptr[rd_vl_index]];        
    wire sample_restart = wr_en && !wr_queue_mode &&        
                          (wr_byte_offset == 0) && (wr_vl_index == rd_vl_index);  
    wire sample_commit = wr_frame_done && !wr_queue_mode &&  
                         (wr_vl_index == rd_vl_index);      
    wire enqueue_now;
    wire dequeue_now = queue_mode[rd_vl_index] &&           
                       rd_en &&                             
                       (frame_cnt[rd_vl_index] != 4'd0) &&  
                       (head_len != 0) &&                   
                       (rd_byte_offset == rd_progress[rd_vl_index]) &&  
                       !sample_restart && !sample_commit &&  
                       (rd_byte_offset == head_len - 1'b1);     
    genvar g;                                               
    generate                                                
        for (g = 0; g < SLOT_NUM; g = g + 1) begin : g_slot_status  
            assign rd_frame_len_all[g*FRAME_LEN_WIDTH +: FRAME_LEN_WIDTH] =  
                (frame_cnt[g] == 0) ? {FRAME_LEN_WIDTH{1'b0}} :  
                 len_fifo[g][fifo_rd_ptr[g]];               
            assign rd_frame_cnt_all[g*(FRAME_CNT_WIDTH+1) +: (FRAME_CNT_WIDTH+1)] =  
                frame_cnt[g];                                   
        end                                                 
    endgenerate

endmodule
