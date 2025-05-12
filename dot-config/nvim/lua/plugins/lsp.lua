return {
  {
    "williamboman/mason.nvim",
    opts = {},
  },
  {
    "williamboman/mason-lspconfig.nvim",
    opts = {
      ensure_installed = { "lua_ls", "ts_ls", "eslint" },
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
      lspconfig.ts_ls.setup({
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
      local timeout = 5000
      require("null-ls").setup({
        debug = false,
        sources = {
          null_ls.builtins.diagnostics.terraform_validate,
          null_ls.builtins.formatting.terraform_fmt,
          null_ls.builtins.formatting.xmllint,
          null_ls.builtins.formatting.gofmt,
          null_ls.builtins.diagnostics.yamllint,
          null_ls.builtins.diagnostics.haml_lint.with({
            command = "bundle",
            args = { "exec", "haml-lint", "--reporter", "json", "$FILENAME" },
          }),
          null_ls.builtins.diagnostics.rubocop.with({
            command = "bundle",
            args = { "exec", "rubocop", "--force-exclusion", "--format", "json", "--stdin", "$FILENAME" },
            timeout = timeout,
          }),
          null_ls.builtins.formatting.rubocop.with({
            command = "bundle",
            args = { "exec", "rubocop", "-a", "--force-exclusion", "--server", "-f", "quiet", "--stderr", "--stdin", "$FILENAME" },
            timeout = timeout,
          }),
        },
        on_attach = function(client, bufnr)
          -- Format on save
          if client.supports_method("textDocument/formatting") then
            vim.api.nvim_clear_autocmds({ group = augroup, buffer = bufnr })
            vim.api.nvim_create_autocmd("BufWritePre", {
              group = augroup,
              buffer = bufnr,
              callback = function()
                vim.lsp.buf.format({ async = false, timeout_ms = timeout })
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
