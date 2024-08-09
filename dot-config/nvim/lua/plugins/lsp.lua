return {
  {
    "williamboman/mason.nvim",
    opts = {},
  },
  {
    "williamboman/mason-lspconfig.nvim",
    opts = {
      ensure_installed = { "lua_ls", "tsserver", "eslint" },
    },
  },
  {
    "neovim/nvim-lspconfig",
    config = function()
      local lspconfig = require("lspconfig")

      vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, {})

      lspconfig.lua_ls.setup({
        on_attach = require("lsp-format").on_attach,
      })
      lspconfig.tsserver.setup({
        on_attach = require("lsp-format").on_attach,
      })
      lspconfig.eslint.setup({
        on_attach = require("lsp-format").on_attach,
      })
    end,
  },
  {
    "nvimtools/none-ls.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    config = function()
      local null_ls = require("null-ls")
      local augroup = vim.api.nvim_create_augroup("LspFormatting", {})
      require("null-ls").setup({
        sources = {
          null_ls.builtins.diagnostics.haml_lint,
          null_ls.builtins.diagnostics.rubocop.with({
            command = "bundle",
            args = { "exec", "rubocop", "--format", "json", "--stdin", "$FILENAME" },
          }),
          null_ls.builtins.formatting.rubocop.with({
            command = "bundle",
            args = { "exec", "rubocop", "-a", "--server", "-f", "quiet", "--stderr", "--stdin", "$FILENAME" },
          }),
        },
        on_attach = function(client, bufnr)
          if client.supports_method("textDocument/formatting") then
            vim.api.nvim_clear_autocmds({ group = augroup, buffer = bufnr })
            vim.api.nvim_create_autocmd("BufWritePre", {
              group = augroup,
              buffer = bufnr,
              callback = function()
                vim.lsp.buf.format({ async = false, timeout_ms = 1000 })
              end,
            })
          end
        end
      })
    end,
  },
  {
    "lukas-reineke/lsp-format.nvim",
    opts = {},
  },
}
