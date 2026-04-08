local M = {}

-- 更新单个插件（带进度回调）
---@param name string
---@param on_progress fun(current: number, total: number, name: string)|nil
---@param on_done fun(ok: boolean, msg: string)
function M.update_one(name, on_progress, on_done)
    if on_progress then
        on_progress(1, 1, name)
    end
    vim.pack.update({ name }, { force = true })
    on_done(true, name .. ' 更新完成')
end

-- 更新全部插件（带进度回调）
---@param on_progress fun(current: number, total: number, name: string)
---@param on_done fun(ok: boolean, msg: string)
function M.update_all(on_progress, on_done)
    local plugins = vim.pack.get(nil, { info = false })
    local total = #plugins

    -- 逐个更新以获取进度
    local function update_next(idx)
        if idx > total then
            on_done(true, '全部插件更新完成')
            return
        end
        local plug = plugins[idx]
        on_progress(idx, total, plug.name)

        vim.pack.update({ plug.name }, { force = true })
        vim.defer_fn(function()
            update_next(idx + 1)
        end, 100)
    end

    update_next(1)
end

-- 卸载插件（无需二次确认，确认已在 UI 中完成）
---@param name string
---@param on_done fun(ok: boolean, msg: string)
function M.delete(name, on_done)
    local ok, err = pcall(function()
        vim.pack.del({ name }, { force = true })
    end)
    if ok then
        on_done(true, name .. ' 已卸载')
    else
        on_done(false, '卸载失败: ' .. tostring(err))
    end
end

-- 修复损坏的插件（删除目录，重启后 vim.pack.add 会重新安装）
---@param name string
---@param path string
---@param on_done fun(ok: boolean, msg: string)
function M.repair(name, path, on_done)
    local choice = vim.fn.confirm(
        '修复插件 "' .. name .. '"？\n将删除损坏的目录，重启 Nvim 后自动重新安装。',
        '&是\n&否',
        2
    )
    if choice ~= 1 then
        on_done(false, '已取消')
        return
    end
    local result = vim.fn.delete(path, 'rf')
    if result == 0 then
        on_done(true, name .. ' 目录已删除，请重启 Nvim 以重新安装')
    else
        on_done(false, '删除失败，请手动删除: ' .. path)
    end
end

return M
