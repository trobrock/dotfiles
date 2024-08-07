return {
	{
		"williamboman/mason.nvim",
		opts = {},
	},
	{
		"williamboman/mason-lspconfig.nvim",
		opts = {
			ensure_installed = { "lua_ls", "tsserver", "rubocop", "ruby_lsp", "eslint" },
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
			lspconfig.rubocop.setup({
				on_attach = require("lsp-format").on_attach,
				cmd = { "mise", "exec", "ruby", "--", "bundle", "exec", "rubocop", "--lsp" },
			})
		end,
	},
	{
		"nvimtools/none-ls.nvim",
		dependencies = {
			"nvim-lua/plenary.nvim",
		},
		opts = function()
			local null_ls = require("null-ls")

			return {
				sources = {
					null_ls.builtins.diagnostics.haml_lint,
				},
			}
		end,
	},
	{
		"lukas-reineke/lsp-format.nvim",
		opts = {},
	},
}
