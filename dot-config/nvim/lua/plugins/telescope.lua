return {
  {
    "nvim-telescope/telescope-fzf-native.nvim",
    build = "make",
    config = function()
      require("telescope").setup()

      require("telescope").load_extension("fzf")
    end,
  },
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "BurntSushi/ripgrep",
    },
    opts = {},
    -- stylua: ignore
    keys = {
      { "<leader>,",       "<cmd>Telescope buffers sort_mru=true sort_lastused=true<cr>",             desc = "Switch Buffer", },
      { "<leader><space>", function() require("telescope.builtin").find_files({ follow = true }) end, desc = "Find Files (Root Dir)", },
      { "<leader>:",       "<cmd>Telescope command_history<cr>",                                      desc = "Command History" },
      { "<leader>/",       function() require("telescope.builtin").live_grep() end,                   desc = "Grep (Root Dir)", },
      { "<leader>#",       "<cmd>Telescope grep_string<cr>",                                          desc = "Grep (word under cursor)", },
      { "<leader>sr",      "<cmd>Telescope resume<cr>",                                                desc = "Resume Last Search" },
    },
  },
  {
    "nvim-telescope/telescope-ui-select.nvim",
    config = function()
      require("telescope").setup({
        extensions = {
          ["ui-select"] = {
            require("telescope.themes").get_dropdown({}),
          },
        },
      })

      require("telescope").load_extension("ui-select")
    end,
  },
  {
    "folke/todo-comments.nvim",
    cmd = { "TodoTelescope" },
    event = { "BufReadPost", "BufWritePost", "BufNewFile" },
    config = true,
    -- stylua: ignore
    keys = {
      { "<leader>st", "<cmd>TodoTelescope<cr>",                         desc = "Todo" },
      { "<leader>sT", "<cmd>TodoTelescope keywords=TODO,FIX,FIXME<cr>", desc = "Todo/Fix/Fixme" },
    },
  },
}
