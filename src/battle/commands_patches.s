"""
In-place patches for the small-VWF battle command window (shorter slot stride, command-id base, format-buffer
pointer).
"""

.import "assets"
.include "config.i"
command_buffer_ptr = 0x97a6 + 0x601  ; old spell lists buffers
command_length = 6
; Command window
.alloc at 0x16fe5a + 6 * 2 {
    .db 0x05, 0x00, command_length + 2, 0x0d
}


.alloc at 0x2b990 {
    lda.b #0x18 + 8
}


{
; ram position of the prebuilt battle windows
    .alloc at 0x16FEAD {
cmd_text_buf_ptrs:
    battle_data_size = command_length * 4 * 5
    .dw command_buffer_ptr
    .dw command_buffer_ptr + battle_data_size
    .dw command_buffer_ptr + battle_data_size * 2
    .dw command_buffer_ptr + battle_data_size * 3
    .dw command_buffer_ptr + battle_data_size * 4
    }


    .alloc at 0x16FE54 {
    .db command_length * 2
    .db 0x0a
    .dw command_buffer_ptr  ; read address
    .dw 0xC1F4 - 2  ; write address
    }


    .alloc at 0x02999F {
    ldx.w #battle_data_size
    }
}
