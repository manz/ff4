--[[
  Trace treasure-menu rolling-buffer state.

  Cinematic: load savestate → wait 5s for menu → DOWN, A, DOWN×6.
  Logs WRAM bytes + exec hit counters at the patched ROM sites.

  Output: stderr + /tmp/treasure_menu_trace.log
]]

dofile("/Users/manz/PyCharmProjects/ff4/tests/lua/lib/ff4test.lua")

local DUMP_LOG = "/tmp/treasure_menu_trace.log"
local logf = io.open(DUMP_LOG, "w")

local function logf_write(msg)
    if logf then logf:write(msg .. "\n") logf:flush() end
end

local hits = {
    init_buffer = 0, main_loop = 0, down_trigger = 0, up_trigger = 0,
    start_down = 0, update_frame = 0,
    d802 = 0, d929 = 0, d933 = 0, d9ea = 0,
    da08 = 0, da57 = 0, da8c = 0,
}
local function bump(k) return function() hits[k] = hits[k] + 1 end end
emu.addMemoryCallback(bump("init_buffer"),  emu.callbackType.exec, 0x01EC1A, 0x01EC1A)
emu.addMemoryCallback(bump("down_trigger"), emu.callbackType.exec, 0x01EC38, 0x01EC38)
emu.addMemoryCallback(bump("up_trigger"),   emu.callbackType.exec, 0x01EC4B, 0x01EC4B)
emu.addMemoryCallback(bump("main_loop"),    emu.callbackType.exec, 0x01EC5E, 0x01EC5E)
emu.addMemoryCallback(bump("start_down"),   emu.callbackType.exec, 0x20B6E4, 0x20B6E4)
emu.addMemoryCallback(bump("update_frame"), emu.callbackType.exec, 0x20B779, 0x20B779)
emu.addMemoryCallback(bump("d802"),         emu.callbackType.exec, 0x01D802, 0x01D802)
emu.addMemoryCallback(bump("d929"),         emu.callbackType.exec, 0x01D929, 0x01D929)
emu.addMemoryCallback(bump("d933"),         emu.callbackType.exec, 0x01D933, 0x01D933)
emu.addMemoryCallback(bump("d9ea"),         emu.callbackType.exec, 0x01D9EA, 0x01D9EA)
emu.addMemoryCallback(bump("da08"),         emu.callbackType.exec, 0x01DA08, 0x01DA08)
emu.addMemoryCallback(bump("da57"),         emu.callbackType.exec, 0x01DA57, 0x01DA57)
emu.addMemoryCallback(bump("da8c"),         emu.callbackType.exec, 0x01DA8C, 0x01DA8C)

local function r8(addr) return ff4.read8(addr) end
local function r16(addr) return ff4.read16(addr) end

local function read_cpu(off)
    return emu.read(off, emu.memType.snesMemory)
end

local function dump_hdma_shadow(t, tag)
    local base = 0x704700
    local lines = { string.format("--- HDMA TABLE @ $70:4700 (snesMemory) [%s] ---", tag) }
    for i = 0, 7 do
        local off = base + i * 3
        local count = read_cpu(off)
        local lo    = read_cpu(off + 1)
        local hi    = read_cpu(off + 2)
        local scr = lo + hi * 256
        if scr >= 0x8000 then scr = scr - 0x10000 end
        table.insert(lines, string.format("  [%d] count=%-3d scroll=%6d (%04X)", i, count, scr, lo + hi * 256))
        if count == 0 then break end
    end
    for _, l in ipairs(lines) do
        t:log(l); logf_write(l)
    end
end

local function snapshot(t, tag)
    local bg3_shadow = r16(0x019F)
    local msg = string.format(
        "[%-18s] joy0=%02X joy1=%02X | $1BC6=%02X $9F=%04X | hdma=%02X scrPos=%02X curRow=%02X selRow=%02X | st=%d rem=%02X anim=%04X buf=%02X edge=%02X slot=%02X base=%04X | D929=%d D933=%d D9EA=%d DA08=%d DA57=%d DA8C=%d trig_d=%d main=%d start_d=%d update=%d",
        tag,
        r8(0x0000), r8(0x0001),
        r8(0x1BC6), bg3_shadow,
        r8(0x1BAE), r8(0x1BB7), r8(0x1BB5), r8(0x1BB3),
        r8(0x1BD8), r8(0x1BD9), r16(0x1BDC),
        r8(0x1BD1), r8(0x1BD2), r8(0x1BD3), r16(0x1BD4),
        hits.d929, hits.d933, hits.d9ea, hits.da08, hits.da57, hits.da8c,
        hits.down_trigger, hits.main_loop, hits.start_down, hits.update_frame)
    t:log(msg)
    logf_write(msg)
end

local t = ff4.test("Treasure Menu Trace")
t.timeout_frames = 1800

t:onState("init", function()
    -- Canary: write known bytes to SRAM via Lua, then read back to check
    -- which memType actually accesses SRAM.
    local canary_off = 0x704700
    local got = {}
    for _, mt in ipairs({
        { name = "snesSaveRam", v = emu.memType.snesSaveRam },
        { name = "snesMemory",  v = emu.memType.snesMemory },
        { name = "cpuMemory",   v = emu.memType.cpuMemory },
    }) do
        if mt.v ~= nil then
            pcall(function()
                emu.write(canary_off, 0xAB, mt.v)
                local back = emu.read(canary_off, mt.v)
                table.insert(got, string.format("%s(%d)=%02X", mt.name, mt.v, back))
            end)
        end
    end
    t:log("SRAM canary: " .. table.concat(got, " "))
    -- Try to start a CPU instruction trace log if Mesen exposes the API.
    local ok = pcall(function()
        emu.startTraceLogger("/tmp/treasure_cpu_trace.log",
            "[ShowExtraInfo] true [ShowEffectiveAddresses] true [Format] {%4X}: {%a}: {%s}")
    end)
    if not ok then
        ok = pcall(function() emu.startTraceLogger("/tmp/treasure_cpu_trace.log") end)
    end
    if ok then t:log("trace logger started → /tmp/treasure_cpu_trace.log")
    else      t:log("emu.startTraceLogger unavailable") end
    t:loadState("battle_end_before_treasure", "wait_menu")
end)

t:onState("wait_menu", function()
    t:wait(300, "after_init")
end)

t:onState("after_init", function()
    snapshot(t, "after_init")
    t:tap("down", 6, "after_down1")
end)

t:onState("after_down1", function()
    t:wait(20, "press_a")
end)

t:onState("press_a", function()
    snapshot(t, "before_A")
    t:tap("a", 6, "after_a")
end)

t:onState("after_a", function()
    t:wait(40, "down_loop_1")
end)

for i = 1, 6 do
    local from = "down_loop_" .. i
    local nxt = "down_settle_" .. i
    t:onState(from, function()
        snapshot(t, "before_DOWN_" .. i)
        t:tap("down", 6, nxt)
    end)
    t:onState(nxt, function()
        snapshot(t, "after_DOWN_" .. i)
        dump_hdma_shadow(t, "after_DOWN_" .. i)
        t:wait(16, i < 6 and ("down_loop_" .. (i + 1)) or "up_loop_1")
    end)
end

local UP_PRESSES = 8  -- need 4 to drain cursor to 0, then more to actually scroll up
for i = 1, UP_PRESSES do
    local from = "up_loop_" .. i
    local nxt  = "up_settle_" .. i
    t:onState(from, function()
        snapshot(t, "before_UP_" .. i)
        t:tap("up", 6, nxt)
    end)
    t:onState(nxt, function()
        snapshot(t, "after_UP_" .. i)
        dump_hdma_shadow(t, "after_UP_" .. i)
        t:wait(16, i < UP_PRESSES and ("up_loop_" .. (i + 1)) or "final")
    end)
end

t:onState("final", function()
    pcall(function() emu.stopTraceLogger() end)
    snapshot(t, "final")
    t:log(string.format("FINAL hits: init=%d main=%d down_trig=%d up_trig=%d start_down=%d update_frame=%d | sites: D802=%d D929=%d D933=%d D9EA=%d DA08=%d DA57=%d DA8C=%d",
        hits.init_buffer, hits.main_loop, hits.down_trigger, hits.up_trigger,
        hits.start_down, hits.update_frame,
        hits.d802, hits.d929, hits.d933, hits.d9ea,
        hits.da08, hits.da57, hits.da8c))
    if logf then logf:close() end
    t:finish()
end)

t:run()
