return {
  "nvim-treesitter/nvim-treesitter",
  dependencies = {
    "RRethy/nvim-treesitter-endwise",
  },
  build = ":TSUpdate",
  config = function()
    local config = require("nvim-treesitter.configs")

    config.setup({
      ensure_installed = { "lua", "javascript", "ruby", "go" },
      auto_install = true,
      highlight = { enable = true, additional_vim_regex_highlighting = false },
      indent = { enabled = true },
      endwise = { enable = true },
    })
  end,
}
