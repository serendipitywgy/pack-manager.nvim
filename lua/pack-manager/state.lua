local M = {}

-- 检测插件目录是否损坏（只有 .git 目录，没有实际文件）
---@param path string
---@return boolean
local function is_broken(path)
    local stat = vim.uv.fs_stat(path)
    if not stat then return false end
    local handle = vim.uv.fs_opendir(path, nil, 10)
    if not handle then return true end
    local entries = vim.uv.fs_readdir(handle)
    vim.uv.fs_closedir(handle)
    if not entries then return true end
    -- 如果目录下只有 .git 一个条目，则认为损坏
    local non_git = vim.tbl_filter(function(e)
        return e.name ~= '.git'
    end, entries)
    return #non_git == 0
end

-- 获取插件的远端最新 commit（用于判断是否可更新）
---@param path string
---@return string|nil
local function get_remote_rev(path)
    local result = vim.system(
        { 'git', '-C', path, 'ls-remote', 'origin', 'HEAD' },
        { text = true, timeout = 5000 }
    ):wait()
    if result.code ~= 0 or not result.stdout then return nil end
    return result.stdout:match('^(%x+)')
end

-- 获取插件本地当前 commit
---@param path string
---@return string|nil
local function get_local_rev(path)
    local result = vim.system(
        { 'git', '-C', path, 'rev-parse', 'HEAD' },
        { text = true, timeout = 3000 }
    ):wait()
    if result.code ~= 0 or not result.stdout then return nil end
    return result.stdout:gsub('%s+', '')
end

-- 获取插件 changelog（最近 20 条 commit）
---@param path string
---@return string[]
function M.get_changelog(path)
    local result = vim.system(
        { 'git', '-C', path, 'log', '--oneline', '-20' },
        { text = true, timeout = 5000 }
    ):wait()
    if result.code ~= 0 or not result.stdout then return { '(无法获取 changelog)' } end
    local lines = {}
    for line in result.stdout:gmatch('[^\n]+') do
        table.insert(lines, '  ' .. line)
    end
    return lines
end

-- 获取所有插件状态
-- 返回 { name, path, active, version, local_rev, status }
-- status: 'ok' | 'outdated' | 'broken' | 'unknown'
---@return table[]
function M.get_all()
    local plugins = vim.pack.get(nil, { info = false })
    local result = {}

    for _, plug in ipairs(plugins) do
        local name = plug.spec.name
        local path = plug.path
        local active = plug.active
        local local_rev = plug.rev or '?'
        local version = plug.spec.version or 'default'
        if type(version) == 'table' then
            version = tostring(version)
        end

        local status
        if is_broken(path) then
            status = 'broken'
        else
            status = 'ok'
        end

        table.insert(result, {
            name = name,
            path = path,
            active = active,
            version = version,
            local_rev = local_rev:sub(1, 8),
            status = status,
        })
    end

    -- 按名称排序
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

return M
