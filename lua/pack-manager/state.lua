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

-- 获取插件描述（从 README.md 第一段获取）
---@param path string
---@return string
function M.get_description(path)
    local readme_names = { 'README.md', 'README.lua', 'README.txt', 'readme.md', 'Readme.md' }
    for _, fname in ipairs(readme_names) do
        local full_path = path .. '/' .. fname
        local stat = vim.uv.fs_stat(full_path)
        if stat and stat.type == 'file' then
            local lines = vim.fn.readfile(full_path)
            if lines and #lines > 0 then
                -- 跳过标题行（前几行以 # 开头）
                local desc_lines = {}
                local started = false
                for _, line in ipairs(lines) do
                    if line:match('^%S') and not line:match('^#') and not line:match('^%+') then
                        started = true
                        table.insert(desc_lines, line)
                    elseif started then
                        break
                    end
                    if #desc_lines >= 2 then
                        break
                    end
                end
                if #desc_lines > 0 then
                    local desc = table.concat(desc_lines, ' ')
                    if #desc > 60 then
                        desc = desc:sub(1, 57) .. '...'
                    end
                    return desc
                end
            end
        end
    end
    return ''
end

-- 获取插件依赖关系（扫描 plugin/ 目录中的 require 调用）
---@param path string
---@return string[]
function M.get_dependencies(path)
    local plugin_dir = path .. '/plugin'
    local stat = vim.uv.fs_stat(plugin_dir)
    if not stat or stat.type ~= 'directory' then
        return {}
    end

    local deps = {}
    local handles = vim.uv.fs_opendir(plugin_dir)
    if not handles then
        return {}
    end

    local entries = {}
    local entry
    repeat
        entry = vim.uv.fs_readdir(handles)
        if entry and #entry > 0 then
            for _, e in ipairs(entry) do
                if e.name:match('%.lua$') then
                    table.insert(entries, e.name)
                end
            end
        end
    until not entry or #entry == 0
    vim.uv.fs_closedir(handles)

    for _, fname in ipairs(entries) do
        local full_path = plugin_dir .. '/' .. fname
        local lines = vim.fn.readfile(full_path)
        if lines then
            for _, line in ipairs(lines) do
                -- 匹配 require('xxx') 或 require("xxx")
                local dep = line:match("require%(['\"])(.-)%1")
                if dep and dep ~= '' and not dep:match('^vim') and not dep:match('^_G') then
                    if not vim.tbl_contains(deps, dep) then
                        table.insert(deps, dep)
                    end
                end
            end
        end
    end

    return deps
end

-- 比较本地和远程版本
---@param path string
---@return string|nil (落后/领先/同步/无法检测)
function M.compare_versions(path)
    local local_rev = get_local_rev(path)
    if not local_rev then
        return nil
    end

    local remote_rev = get_remote_rev(path)
    if not remote_rev then
        return nil
    end

    if local_rev == remote_rev then
        return '同步'
    end

    -- 计算 commits 差异
    local result = vim.system(
        { 'git', '-C', path, 'log', '--oneline', remote_rev .. '..' .. local_rev },
        { text = true, timeout = 5000 }
    ):wait()

    if result.code == 0 and result.stdout then
        local count = 0
        for _ in result.stdout:gmatch('[^\n]+') do
            count = count + 1
        end
        if count > 0 then
            return '领先 ' .. count .. ' commits'
        end
    end

    -- 检查是否落后
    result = vim.system(
        { 'git', '-C', path, 'log', '--oneline', local_rev .. '..' .. remote_rev },
        { text = true, timeout = 5000 }
    ):wait()

    if result.code == 0 and result.stdout then
        local count = 0
        for _ in result.stdout:gmatch('[^\n]+') do
            count = count + 1
        end
        if count > 0 then
            return '落后 ' .. count .. ' commits'
        end
    end

    return nil
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
