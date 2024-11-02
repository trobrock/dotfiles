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

vim.keymap.set("n", "]<Space>", "o<Esc>", { desc = "New line below" })
vim.keymap.set("n", "[<Space>", "O<Esc>", { desc = "New line above" })
vim.keymap.set("n", "<C-t>", ":tabnew<CR>", { desc = "New tab" })
vim.keymap.set("n", "]t", "gt", { desc = "Next tab" })
vim.keymap.set("n", "[t", "gT", { desc = "Previous tab" })

-- vim autocmd on focus lost
vim.cmd("autocmd BufLeave,FocusLost * silent! wall")

-- enable local .nvim.lua config
vim.opt.exrc = true

--fix terraform and hcl comment string
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("FixTerraformCommentString", { clear = true }),
  callback = function(ev)
    vim.bo[ev.buf].commentstring = "# %s"
  end,
  pattern = { "terraform", "hcl" },
})
