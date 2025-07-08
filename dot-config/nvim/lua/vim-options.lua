vim.g.mapleader = " "

vim.cmd("set nocompatible")

-- Correct tabs
vim.cmd("set expandtab")
vim.cmd("set tabstop=2")
vim.cmd("set softtabstop=2")
vim.cmd("set shiftwidth=2")

-- Use the system clipboard
vim.opt.clipboard = "unnamedplus"

-- set relative number and show numbers
vim.cmd("set number")
vim.cmd("set relativenumber")

-- No wrapping
vim.opt.wrap = false

-- New lines
vim.keymap.set("n", "]<Space>", "o<Esc>", { desc = "New line below" })
vim.keymap.set("n", "[<Space>", "O<Esc>", { desc = "New line above" })

-- Tabs
vim.keymap.set("n", "<C-t>", ":tabnew<CR>", { desc = "New tab" })
vim.keymap.set("n", "]t", "gt", { desc = "Next tab" })
vim.keymap.set("n", "[t", "gT", { desc = "Previous tab" })

-- Save the file when it loses focus
vim.cmd("autocmd BufLeave,FocusLost * silent! wall")

-- enable local .nvim.lua config, for project specific settings
vim.opt.exrc = true

-- restore cursor position when reopening files
vim.api.nvim_create_autocmd("BufReadPost", {
  group = vim.api.nvim_create_augroup("RestoreCursorPosition", { clear = true }),
  callback = function(ev)
    local mark = vim.api.nvim_buf_get_mark(ev.buf, '"')
    if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(ev.buf) then
      vim.api.nvim_win_set_cursor(0, mark)
    end
  end,
})

--fix terraform and hcl comment string
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("FixTerraformCommentString", { clear = true }),
  callback = function(ev)
    vim.bo[ev.buf].commentstring = "# %s"
  end,
  pattern = { "terraform", "hcl" },
})

-- copy current file path to clipboard
vim.keymap.set("n", "cp", ":let @+ = expand('%:p')<CR>", { desc = "Copy current file path to clipboard" })

-- configure diagnostic display
vim.diagnostic.config({
  virtual_text = true,
  signs = true,
  underline = true,
  update_in_insert = false,
  severity_sort = false,
})
vim.diagnostic.config({
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = '',
      [vim.diagnostic.severity.WARN] = '',
      [vim.diagnostic.severity.INFO] = '',
      [vim.diagnostic.severity.HINT] = '󰌵',
    },
  }
})
