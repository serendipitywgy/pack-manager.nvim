local M = {}

-- 更新单个插件
---@param name string
---@param on_done fun(ok: boolean, msg: string)
function M.update_one(name, on_done)
    vim.pack.update({ name }, { force = true })
    on_done(true, name .. ' 更新完成')
end

-- 更新全部插件
---@param on_done fun(ok: boolean, msg: string)
function M.update_all(on_done)
    vim.pack.update(nil, { force = true })
    on_done(true, '全部插件更新完成')
end

-- 卸载插件（带二次确认）
---@param name string
---@param on_done fun(ok: boolean, msg: string)
function M.delete(name, on_done)
    local choice = vim.fn.confirm(
        '确认卸载插件 "' .. name .. '" ？\n此操作将删除插件目录，无法撤销。',
        '&是\n&否',
        2
    )
    if choice ~= 1 then
        on_done(false, '已取消')
        return
    end
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
