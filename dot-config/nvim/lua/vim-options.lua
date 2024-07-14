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
