return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    dependencies = {
      "RRethy/nvim-treesitter-endwise",
    },
    config = function()
      local ts = require("nvim-treesitter")
      ts.setup()

      ts.install({
        "lua", "javascript", "ruby", "go", "yaml", "vim",
        "markdown", "markdown_inline", "html", "dockerfile", "gitignore",
      })

      vim.api.nvim_create_autocmd("FileType", {
        callback = function(args)
          local buf = args.buf
          if vim.bo[buf].buftype ~= "" then return end
          if not pcall(vim.treesitter.start, buf) then return end
          vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end,
      })

      -- Incremental selection using Nvim 0.12 built-in `an`/`in` tree-sitter selectors.
      vim.keymap.set("n", "<C-space>", "van", { remap = true, desc = "Start incremental selection" })
      vim.keymap.set("x", "<C-space>", "an", { remap = true, desc = "Expand selection to parent node" })
      vim.keymap.set("x", "<BS>", "in", { remap = true, desc = "Shrink selection to child node" })
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    config = function()
      require("nvim-treesitter-textobjects").setup({
        select = { lookahead = true },
        move = { set_jumps = true },
      })

      local select = require("nvim-treesitter-textobjects.select")
      local function sel(query)
        return function() select.select_textobject(query, "textobjects") end
      end
      vim.keymap.set({ "x", "o" }, "B=", sel("@block.outer"),    { desc = "outer block" })
      vim.keymap.set({ "x", "o" }, "b=", sel("@block.inner"),    { desc = "inner block" })
      vim.keymap.set({ "x", "o" }, "F=", sel("@function.outer"), { desc = "outer function" })
      vim.keymap.set({ "x", "o" }, "f=", sel("@function.inner"), { desc = "inner function" })

      local move = require("nvim-treesitter-textobjects.move")
      local function nstart(query, group) return function() move.goto_next_start(query, group or "textobjects") end end
      local function nend(query)          return function() move.goto_next_end(query, "textobjects") end end
      local function pstart(query)        return function() move.goto_previous_start(query, "textobjects") end end
      local function pend(query)          return function() move.goto_previous_end(query, "textobjects") end end

      local modes = { "n", "x", "o" }
      vim.keymap.set(modes, "]f", nstart("@call.outer"),        { desc = "Next function call start" })
      vim.keymap.set(modes, "]m", nstart("@function.outer"),    { desc = "Next method/function def start" })
      vim.keymap.set(modes, "]c", nstart("@class.outer"),       { desc = "Next class start" })
      vim.keymap.set(modes, "]i", nstart("@conditional.outer"), { desc = "Next conditional start" })
      vim.keymap.set(modes, "]l", nstart("@loop.outer"),        { desc = "Next loop start" })
      vim.keymap.set(modes, "]s", nstart("@local.scope", "locals"), { desc = "Next scope" })
      vim.keymap.set(modes, "]z", nstart("@fold", "folds"),     { desc = "Next fold" })

      vim.keymap.set(modes, "]F", nend("@call.outer"),        { desc = "Next function call end" })
      vim.keymap.set(modes, "]M", nend("@function.outer"),    { desc = "Next method/function def end" })
      vim.keymap.set(modes, "]C", nend("@class.outer"),       { desc = "Next class end" })
      vim.keymap.set(modes, "]I", nend("@conditional.outer"), { desc = "Next conditional end" })
      vim.keymap.set(modes, "]L", nend("@loop.outer"),        { desc = "Next loop end" })

      vim.keymap.set(modes, "[f", pstart("@call.outer"),        { desc = "Prev function call start" })
      vim.keymap.set(modes, "[m", pstart("@function.outer"),    { desc = "Prev method/function def start" })
      vim.keymap.set(modes, "[c", pstart("@class.outer"),       { desc = "Prev class start" })
      vim.keymap.set(modes, "[i", pstart("@conditional.outer"), { desc = "Prev conditional start" })
      vim.keymap.set(modes, "[l", pstart("@loop.outer"),        { desc = "Prev loop start" })

      vim.keymap.set(modes, "[F", pend("@call.outer"),        { desc = "Prev function call end" })
      vim.keymap.set(modes, "[M", pend("@function.outer"),    { desc = "Prev method/function def end" })
      vim.keymap.set(modes, "[C", pend("@class.outer"),       { desc = "Prev class end" })
      vim.keymap.set(modes, "[I", pend("@conditional.outer"), { desc = "Prev conditional end" })
      vim.keymap.set(modes, "[L", pend("@loop.outer"),        { desc = "Prev loop end" })
    end,
  },
}
