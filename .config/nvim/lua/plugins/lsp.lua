return {
	{
		"williamboman/mason.nvim",
		opts = {},
	},
	{
		"williamboman/mason-lspconfig.nvim",
		opts = {
			ensure_installed = { "lua_ls", "tsserver", "rubocop", "ruby_lsp" },
		},
	},
	{
		"neovim/nvim-lspconfig",
		config = function()
			local lspconfig = require("lspconfig")

			vim.keymap.set("n", "K", vim.lsp.buf.hover, {})
			vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, {})

			lspconfig.lua_ls.setup({
				on_attach = require("lsp-format").on_attach,
			})
			lspconfig.tsserver.setup({
				on_attach = require("lsp-format").on_attach,
			})
			lspconfig.rubocop.setup({
				on_attach = require("lsp-format").on_attach,
			})
			lspconfig.ruby_lsp.setup({
				on_attach = require("lsp-format").on_attach,
			})
		end,
	},
	{
		"lukas-reineke/lsp-format.nvim",
		opts = {},
	},
}
