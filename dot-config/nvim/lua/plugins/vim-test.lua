return {
  "vim-test/vim-test",
  dependencies = {
    "preservim/vimux"
  },
  keys = {
    { "<leader>tr", "<cmd>TestNearest<cr>", desc = "Run nearest test" },
    { "<leader>tf", "<cmd>TestFile<cr>",    desc = "Run current file" },
    { "<leader>tl", "<cmd>TestLast<cr>",    desc = "Run last test" },
  },
  config = function()
    vim.cmd("let test#strategy = 'vimux'")
  end
}
