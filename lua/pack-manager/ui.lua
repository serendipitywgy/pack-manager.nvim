local M = {}

local state = require('pack-manager.state')
local actions = require('pack-manager.actions')

-- 窗口和 buffer 句柄
local win = nil
local buf = nil

-- 插件数据缓存
local plugins = {}

-- namespace for highlights
local ns = vim.api.nvim_create_namespace('pack_manager')

local STATUS_ICONS = {
    ok      = '✓',
    broken  = '✗',
    unknown = '?',
}

local HELP_LINES = {
    '  快捷键帮助:',
    '  U      更新全部插件',
    '  u      更新光标所在插件',
    '  d      卸载光标所在插件',
    '  r      修复损坏的插件',
    '  l      查看 changelog',
    '  i      查看详情',
    '  ?      切换帮助显示',
    '  q / <Esc>  关闭窗口',
}

local show_help = false
local show_changelog_for = nil  -- 当前展开 changelog 的插件名
local confirm_for = nil    -- 当前正在确认删除的插件名
local show_detail_for = nil  -- 当前展开详情的插件名

-- 缓存详情信息
local detail_cache = {}

-- 生成窗口内容行
---@return string[], table[]  lines, highlights {line, col_start, col_end, hl_group}
local function render_lines()
    local lines = {}
    local hls = {}

    -- 标题
    table.insert(lines, '  Pack Manager')
    table.insert(lines, '  U:更新全部  u:更新  d:卸载  r:修复  l:changelog  ?:帮助  q:退出')
    table.insert(lines, string.rep('─', 56))

    local plugin_start_line = #lines  -- 插件列表从这行开始（0-indexed 是 plugin_start_line）

    if #plugins == 0 then
        table.insert(lines, '  (暂无 vim.pack 管理的插件)')
    end

    for i, plug in ipairs(plugins) do
        local icon = STATUS_ICONS[plug.status] or '?'
        local version = tostring(plug.version)
        if #version > 12 then version = version:sub(1, 12) end

        local active_mark = plug.active and '' or ' [inactive]'
        local line = string.format(
            '  %s %-30s %-14s %s%s',
            icon,
            plug.name,
            version,
            plug.local_rev,
            active_mark
        )
        table.insert(lines, line)

        -- highlight
        local lnum = plugin_start_line + i - 1  -- 0-indexed
        local hl_group
        if plug.status == 'ok' then
            hl_group = 'DiagnosticOk'
        elseif plug.status == 'broken' then
            hl_group = 'DiagnosticError'
        else
            hl_group = 'DiagnosticWarn'
        end
        table.insert(hls, { line = lnum, col_start = 2, col_end = 3, hl_group = hl_group })

        -- 展开 changelog
        if show_changelog_for == plug.name then
            local cl = state.get_changelog(plug.path)
            table.insert(lines, '  ┌─ Changelog ─────────────────────────────────────')
            table.insert(hls, { line = #lines - 1, col_start = 0, col_end = -1, hl_group = 'Comment' })
            for _, cl_line in ipairs(cl) do
                table.insert(lines, cl_line)
                table.insert(hls, { line = #lines - 1, col_start = 0, col_end = -1, hl_group = 'Comment' })
            end
            table.insert(lines, '  └─────────────────────────────────────────────────')
            table.insert(hls, { line = #lines - 1, col_start = 0, col_end = -1, hl_group = 'Comment' })
        end

        -- 确认删除模式
        if confirm_for == plug.name then
            table.insert(lines, '  ┌─ 确认卸载 ' .. plug.name .. '？ ──────────────────────────────')
            table.insert(hls, { line = #lines - 1, col_start = 0, col_end = -1, hl_group = 'DiagnosticWarn' })
            table.insert(lines, '  │  [Enter] 确认删除    [q] 取消')
            table.insert(hls, { line = #lines - 1, col_start = 0, col_end = -1, hl_group = 'Comment' })
            table.insert(lines, '  └─────────────────────────────────────────────────')
            table.insert(hls, { line = #lines - 1, col_start = 0, col_end = -1, hl_group = 'Comment' })
        end

        -- 详情展开模式
        if show_detail_for == plug.name and detail_cache[plug.name] then
            local detail = detail_cache[plug.name]
            table.insert(lines, '  ┌─ 详情 ──────────────────────────────────────')
            table.insert(hls, { line = #lines - 1, col_start = 0, col_end = -1, hl_group = 'Comment' })
            if detail.description and detail.description ~= '' then
                table.insert(lines, '  │ 描述: ' .. detail.description)
                table.insert(hls, { line = #lines - 1, col_start = 0, col_end = -1, hl_group = 'Comment' })
            end
            if #detail.dependencies > 0 then
                table.insert(lines, '  │ 依赖: ' .. table.concat(detail.dependencies, ', '))
                table.insert(hls, { line = #lines - 1, col_start = 0, col_end = -1, hl_group = 'Comment' })
            else
                table.insert(lines, '  │ 依赖: (无)')
                table.insert(hls, { line = #lines - 1, col_start = 0, col_end = -1, hl_group = 'Comment' })
            end
            if detail.version_compare then
                table.insert(lines, '  │ 版本: ' .. detail.version_compare)
                table.insert(hls, { line = #lines - 1, col_start = 0, col_end = -1, hl_group = 'Comment' })
            end
            table.insert(lines, '  └─────────────────────────────────────────────────')
            table.insert(hls, { line = #lines - 1, col_start = 0, col_end = -1, hl_group = 'Comment' })
        end
    end

    table.insert(lines, string.rep('─', 56))

    -- 帮助
    if show_help then
        for _, hl in ipairs(HELP_LINES) do
            table.insert(lines, hl)
        end
    end

    return lines, hls
end

-- 刷新 buffer 内容
local function refresh()
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

    plugins = state.get_all()
    local lines, hls = render_lines()

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    -- 清除旧 highlight，应用新的
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for _, hl in ipairs(hls) do
        local col_end = hl.col_end == -1 and -1 or hl.col_end
        vim.api.nvim_buf_add_highlight(buf, ns, hl.hl_group, hl.line, hl.col_start, col_end)
    end
end

-- 根据光标行获取对应的插件（考虑 changelog 和详情展开）
---@return table|nil
local function get_plugin_at_cursor()
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return nil end
    local cursor_line = vim.api.nvim_win_get_cursor(win)[1]  -- 1-indexed
    -- 头部固定 3 行（标题+操作栏+分隔线）
    local HEADER = 3
    if cursor_line <= HEADER then return nil end

    local current_line = HEADER
    for _, plug in ipairs(plugins) do
        current_line = current_line + 1
        if cursor_line == current_line then
            return plug
        end
        -- 如果这个插件展开了 changelog
        if show_changelog_for == plug.name then
            local cl = state.get_changelog(plug.path)
            current_line = current_line + #cl + 2  -- header + lines + footer
        end
        -- 如果展开详情
        if show_detail_for == plug.name and detail_cache[plug.name] then
            local detail = detail_cache[plug.name]
            local detail_lines = 2  -- header + footer
            if detail.description and detail.description ~= '' then detail_lines = detail_lines + 1 end
            if #detail.dependencies > 0 then detail_lines = detail_lines + 1 end
            if detail.version_compare then detail_lines = detail_lines + 1 end
            current_line = current_line + detail_lines
        end
    end
    return nil
end

-- 显示状态消息（写到最后一行临时提示）
---@param msg string
local function set_status(msg)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
    vim.bo[buf].modifiable = true
    local line_count = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_buf_set_lines(buf, line_count, -1, false, { '  ' .. msg })
    vim.bo[buf].modifiable = false
end

-- 关闭窗口
local function close()
    if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
    end
    win = nil
    buf = nil
    show_changelog_for = nil
    show_help = false
    confirm_for = nil
    show_detail_for = nil
    detail_cache = {}
end

-- 设置 buffer-local 快捷键
local function set_keymaps()
    local function map(key, fn)
        vim.keymap.set('n', key, fn, { buffer = buf, nowait = true, silent = true })
    end

    -- 关闭 (在确认模式下由上面重新定义为 cancel + close)

    -- 更新全部（带进度条）
    map('U', function()
        set_status('⟳ 正在更新全部插件...')
        local plugins_list = vim.pack.get(nil, { info = false })
        local total = #plugins_list
        local current = 0
        local function do_update()
            current = current + 1
            if current > total then
                refresh()
                set_status('✓ 全部插件更新完成')
                return
            end
            local plug = plugins_list[current]
            local percent = math.floor(current / total * 100)
            local bar_len = 20
            local filled = math.floor(bar_len * current / total)
            local bar = string.rep('█', filled) .. string.rep('░', bar_len - filled)
            set_status(string.format('[%s] %d%% (%d/%d) 正在更新 %s...', bar, percent, current, total, plug.name))
            vim.pack.update({ plug.name }, { force = true })
            vim.defer_fn(do_update, 50)
        end
        do_update()
    end)

    -- 更新当前插件
    map('u', function()
        local plug = get_plugin_at_cursor()
        if not plug then return end
        set_status('⟳ 正在更新 ' .. plug.name .. '...')
        vim.pack.update({ plug.name }, { force = true })
        vim.defer_fn(function()
            refresh()
            set_status('✓ ' .. plug.name .. ' 更新完成')
        end, 100)
    end)

    -- 卸载当前插件 - 进入确认模式
    map('d', function()
        local plug = get_plugin_at_cursor()
        if not plug then return end
        confirm_for = plug.name
        refresh()
    end)

    -- 修复损坏插件
    map('r', function()
        local plug = get_plugin_at_cursor()
        if not plug then return end
        if plug.status ~= 'broken' then
            set_status('  ' .. plug.name .. ' 未损坏，无需修复')
            return
        end
        actions.repair(plug.name, plug.path, function(ok, msg)
            vim.schedule(function()
                if ok then
                    refresh()
                end
                set_status(ok and ('✓ ' .. msg) or ('✗ ' .. msg))
            end)
        end)
    end)

    -- 确认删除 - Enter 或 y 执行删除
    local function confirm_delete()
        if not confirm_for then return end
        local plug
        for _, p in ipairs(plugins) do
            if p.name == confirm_for then
                plug = p
                break
            end
        end
        if not plug then
            confirm_for = nil
            refresh()
            return
        end
        set_status('⟳ 正在卸载 ' .. plug.name .. '...')
        actions.delete(plug.name, function(ok, msg)
            vim.schedule(function()
                confirm_for = nil
                if ok then
                    refresh()
                end
                set_status(ok and ('✓ ' .. msg) or ('✗ ' .. msg))
            end)
        end)
    end
    map('<Enter>', confirm_delete)
    map('y', confirm_delete)

    -- 取消确认 - q, n 或 Esc
    local function cancel_confirm()
        confirm_for = nil
        set_status('  已取消')
        refresh()
    end
    map('q', function()
        if confirm_for then cancel_confirm() else close() end
    end)
    map('n', cancel_confirm)
    map('<Esc>', function()
        if confirm_for then cancel_confirm() else close() end
    end)

    -- 展开详情 - 按 i 键
    map('i', function()
        local plug = get_plugin_at_cursor()
        if not plug then return end
        if show_detail_for == plug.name then
            show_detail_for = nil
        else
            show_detail_for = plug.name
            -- 异步获取详情
            vim.schedule(function()
                if not detail_cache[plug.name] then
                    detail_cache[plug.name] = {
                        description = state.get_description(plug.path),
                        dependencies = state.get_dependencies(plug.path),
                        version_compare = state.compare_versions(plug.path),
                    }
                end
                if show_detail_for == plug.name then
                    refresh()
                end
            end)
        end
        refresh()
    end)

    -- 查看 changelog
    map('l', function()
        local plug = get_plugin_at_cursor()
        if not plug then return end
        if show_changelog_for == plug.name then
            show_changelog_for = nil
        else
            show_changelog_for = plug.name
        end
        refresh()
    end)

    -- 切换帮助
    map('?', function()
        show_help = not show_help
        refresh()
    end)
end

-- 打开浮动窗口
function M.open()
    -- 如果已打开则聚焦
    if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_set_current_win(win)
        refresh()
        return
    end

    -- 创建 buffer
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = 'pack-manager'

    -- 计算窗口大小和位置
    local width = math.min(70, vim.o.columns - 4)
    local height = math.min(30, vim.o.lines - 6)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    -- 创建浮动窗口
    win = vim.api.nvim_open_win(buf, true, {
        relative = 'editor',
        width = width,
        height = height,
        row = row,
        col = col,
        style = 'minimal',
        border = 'rounded',
        title = ' Pack Manager ',
        title_pos = 'center',
    })

    vim.wo[win].wrap = false
    vim.wo[win].cursorline = true
    vim.wo[win].winhighlight = 'Normal:NormalFloat,CursorLine:Visual'

    set_keymaps()
    refresh()

    -- 关闭时清理
    vim.api.nvim_create_autocmd('WinClosed', {
        pattern = tostring(win),
        once = true,
        callback = function()
            win = nil
            buf = nil
            show_changelog_for = nil
            show_help = false
        end,
    })
end

return M
