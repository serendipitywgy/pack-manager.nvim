# pack-manager.nvim

基于 Neovim 内置 `vim.pack` API 的轻量级插件管理器。

## 功能

- 查看已安装插件列表
- 更新单个或全部插件（带进度条）
- 卸载插件（带 UI 确认）
- 修复损坏的插件
- 查看插件 changelog
- 查看插件详情（描述、依赖、版本对比）

## 安装

```lua
vim.opt.runtimepath:prepend(vim.fn.stdpath('config') .. '/pack-manager.nvim')
```

## 使用

在 Neovim 中运行：

```vim
:lua require('pack-manager').open()
```

或添加快捷键：

```lua
vim.keymap.set('n', '<leader>pm', require('pack-manager').open)
```

## 快捷键

| 按键 | 功能 |
|------|------|
| `U` | 更新全部插件（带进度条） |
| `u` | 更新光标所在插件 |
| `d` | 卸载光标所在插件 |
| `r` | 修复损坏的插件 |
| `l` | 查看 changelog |
| `i` | 查看详情（描述、依赖、版本） |
| `?` | 显示/隐藏帮助 |
| `Enter` | 确认删除（在确认模式下） |
| `y` | 确认删除（在确认模式下） |
| `q` | 取消/关闭 |
| `Esc` | 取消/关闭 |

## 确认模式

按 `d` 后进入确认模式：

```
✓ windsurf.vim              default        3c0a4f8a  
┌─ 确认卸载 windsurf.vim？ ──────────────────────────────
│  [Enter] 确认删除    [q] 取消
└─────────────────────────────────────────────────
```

- `Enter` 或 `y` → 确认删除
- `q` 或 `n` 或 `Esc` → 取消

## 详情模式

按 `i` 展开查看插件详情：

```
✓ windsurf.vim              default        3c0a4f8a  
┌─ 详情 ──────────────────────────────────────
│ 描述: Windsurf AI code completion for nvim
│ 依赖: blink.cmp, nvim-lspconfig
│ 版本: 落后 5 commits
└─────────────────────────────────────────────────
```

- **描述**: 从插件 README.md 自动提取
- **依赖**: 扫描 plugin/ 目录中的 require() 调用
- **版本**: 与远程仓库对比，显示领先/落后/同步

## 更新进度条

按 `U` 更新全部插件时显示进度：

```
[████████████░░░░░░░░] 60% (3/5) 正在更新 clangd...
```