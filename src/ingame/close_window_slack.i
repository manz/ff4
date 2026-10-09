"""Bank $01 room left by vanilla CloseWindow's 25-frame loop, dead since the windows open at once."""
.pool close_window_slack {
    range 0x01841A 0x018456
    strategy order
}
