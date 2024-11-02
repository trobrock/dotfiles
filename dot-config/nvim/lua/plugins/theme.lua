return {
  "catppuccin/nvim",
  name = "catppuccin",
  priority = 1000,
  config = function()
    require("catppuccin").setup({
      flavour = "mocha",   -- latte, frappe, macchiato, mocha
      dim_inactive = {
        enabled = true,    -- dims the background color of inactive window
        shade = "dark",
        percentage = 0.15, -- percentage of the shade to apply to the inactive window
      },
      default_integrations = true,
      integrations = {
        cmp = true,
        gitsigns = true,
        nvimtree = true,
        treesitter = true,
        fzf = true,
        markdown = true,
        mason = true,
        noice = true,
        telescope = {
          enabled = true,
        }
      },
    })

    -- setup must be called before loading
    vim.cmd.colorscheme "catppuccin"
  end
}
