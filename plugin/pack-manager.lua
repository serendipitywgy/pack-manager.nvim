-- 注册用户命令和快捷键
vim.api.nvim_create_user_command('Pack', function()
    require('pack-manager').open()
end, { desc = 'Open Pack Manager' })

vim.keymap.set('n', '<leader>P', function()
    require('pack-manager').open()
end, { desc = 'Pack Manager', silent = true })
