return {
  "stevearc/conform.nvim",
  event = { "BufWritePre" },
  cmd = { "ConformInfo" },
  keys = {
    {
      -- Customize or remove this keymap to your liking
      "<leader>f",
      function()
        require("conform").format({ async = true, lsp_fallback = true })
      end,
      mode = "",
      desc = "Format buffer",
    },
  },

  opts = {
    formatters_by_ft = {
      lua = { "stylua" },
      ruby = { "rubocop" },
    },
    format_on_save = {
      timeout_ms = 1000,
      lsp_fallback = true
    }
  },
}
