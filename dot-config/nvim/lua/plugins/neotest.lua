return {
	"nvim-neotest/neotest",
	dependencies = {
		"nvim-neotest/nvim-nio",
		"nvim-lua/plenary.nvim",
		"antoinemadec/FixCursorHold.nvim",
		"nvim-treesitter/nvim-treesitter",
		"zidhuss/neotest-minitest",
		"nvim-neotest/neotest-plenary",
	},
	opts = function()
		return {
			adapters = {
				require("neotest-minitest"),
				require("neotest-plenary"),
			},
		}
	end,
  -- stylua: ignore
  keys = {
    { '<leader>r',  function() require("neotest").run.run() end,                   desc = 'Run current test' },
    { '<leader>R',  function() require("neotest").run.run(vim.fn.expand("%")) end, desc = 'Run current test' },
    { '<leader>to', function() require("neotest").output_panel.toggle() end,       desc = 'Toggle test output window' }
  }
,
}
