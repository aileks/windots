vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.cursorline = true
vim.opt.scrolloff = 8
vim.opt.termguicolors = true
vim.opt.showtabline = 2
vim.opt.wildmode = 'longest:full,full'
vim.opt.linebreak = true
vim.opt.showbreak = '...'
vim.opt.list = true
vim.opt.listchars = { tab = '→ ', trail = '·', nbsp = '␣' }
vim.opt.pumheight = 10
vim.opt.shortmess:append('c')
vim.opt.smartindent = true
vim.opt.expandtab = true
vim.opt.smarttab = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.softtabstop = 2
vim.opt.copyindent = true
vim.opt.preserveindent = true
vim.opt.whichwrap:append('<,>,h,l')
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.updatetime = 300
vim.opt.timeoutlen = 500
vim.opt.undofile = true
vim.opt.backup = true
vim.opt.backupdir:remove('.')
vim.opt.mousemodel = 'extend'
vim.opt.errorbells = false
vim.opt.splitbelow = true
vim.opt.splitright = true
vim.opt.clipboard = 'unnamedplus'

local map = vim.keymap.set

map('n', '<Esc>', '<cmd>nohlsearch<CR>', { silent = true })

map('n', 'j', 'gj')
map('n', 'k', 'gk')

map('n', '<C-h>', '<C-w>h')
map('n', '<C-j>', '<C-w>j')
map('n', '<C-k>', '<C-w>k')
map('n', '<C-l>', '<C-w>l')

map('n', '<C-d>', '<C-d>zz')
map('n', '<C-u>', '<C-u>zz')
map('n', 'n', 'nzzzv')
map('n', 'N', 'Nzzzv')

map('v', '<', '<gv')
map('v', '>', '>gv')
map('v', 'J', ":m '>+1<CR>gv=gv", { silent = true })
map('v', 'K', ":m '<-2<CR>gv=gv", { silent = true })
map('x', 'p', '"_dP')

map('n', '<leader>w', '<cmd>write<CR>', { desc = 'Save' })
map('n', '<leader>q', '<cmd>quit<CR>', { desc = 'Quit' })
map('n', '<leader>e', '<cmd>Explore<CR>', { desc = 'File explorer' })

vim.api.nvim_create_autocmd('TextYankPost', {
  callback = function()
    vim.hl.on_yank({ timeout = 200 })
  end,
})

local plugins = {
  { src = 'https://github.com/aileks/cinder-grove.nvim.git' },
  { src = 'https://github.com/nvim-lualine/lualine.nvim' },
  { src = 'https://github.com/lukas-reineke/indent-blankline.nvim' },
  { src = 'https://github.com/YousefHadder/markdown-plus.nvim' },
}

if vim.pack then
  vim.pack.add(plugins)
else
  local package_root = vim.fn.stdpath('data') .. '/site/pack/dotfiles/opt'
  vim.fn.mkdir(package_root, 'p')
  for _, plugin in ipairs(plugins) do
    local name = plugin.src:match('/([^/]+)$')
    local path = package_root .. '/' .. name
    if vim.fn.isdirectory(path) == 0 then
      vim.fn.system({ 'git', 'clone', '--filter=blob:none', '--depth=1', plugin.src, path })
      if vim.v.shell_error ~= 0 then
        error('Failed to install Neovim plugin: ' .. name)
      end
    end
    vim.cmd.packadd(name)
  end
end

require('cinder-grove').setup({ transparent = true })
vim.cmd.colorscheme('cinder-grove')

require('lualine').setup({
  options = {
    theme = 'auto',
    icons_enabled = false,
    component_separators = '|',
    section_separators = '',
  },
})

require('ibl').setup()

require('markdown-plus').setup()
