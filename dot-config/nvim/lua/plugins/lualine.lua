return {
  "nvim-lualine/lualine.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  opts = function()
    return {
      options = {
        theme = "catppuccin",
      },
      sections = {
        lualine_a = { "mode" },
        lualine_b = {},
        lualine_c = {
          { "filename", path = 1 },
        },
        lualine_x = { "encoding", "fileformat", "filetype" },
        lualine_y = { "progress" },
        lualine_z = { "diff" },
      },
    }
  end,
}
