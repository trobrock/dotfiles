return {
  "nvim-neotest/neotest",
  dependencies = {
    "nvim-neotest/nvim-nio",
    "nvim-lua/plenary.nvim",
    "antoinemadec/FixCursorHold.nvim",
    "nvim-treesitter/nvim-treesitter",
    "zidhuss/neotest-minitest",
    "olimorris/neotest-rspec",
    "nvim-neotest/neotest-plenary",
  },
  opts = function()
    return {
      adapters = {
        require("neotest-minitest"),
        require("neotest-rspec")({
          rspec_command = vim.tbl_flatten({ "rspec" }),
        }),
        require("neotest-plenary"),
      },
      discovery = {
        -- Drastically improve performance in ginormous projects by
        -- only AST-parsing the currently opened buffer.
        enabled = false,
        -- Number of workers to parse files concurrently.
        -- A value of 0 automatically assigns number based on CPU.
        -- Set to 1 if experiencing lag.
        concurrent = 1,
      },
      running = {
        -- Run tests concurrently when an adapter provides multiple commands to run.
        concurrent = true,
      },
      summary = {
        -- Enable/disable animation of icons.
        animated = false,
      },
    }
  end,
  keys = {
    { '<leader>tr', function() require("neotest").run.run() end,                   desc = 'Run current test' },
    { '<leader>tR', function() require("neotest").run.run(vim.fn.expand("%")) end, desc = 'Run current test file' },
    { '<leader>to', function() require("neotest").output_panel.toggle() end,       desc = 'Toggle test output window' },
    { '<leader>ts', function() require("neotest").summary.toggle() end,            desc = 'Toggle test summary' },
  },
}
