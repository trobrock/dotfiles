-- Enable word wrap for markdown files
vim.opt_local.wrap = true

-- Enable softwrapping (visually wraps without inserting linebreaks)
vim.opt_local.linebreak = true

-- Indents wrapped lines to match the start of the line
vim.opt_local.breakindent = true

-- Set a max text width at 80 columns (optional)
-- vim.opt_local.textwidth = 80

-- Use j and k to navigate through wrapped lines intuitively
vim.keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, buffer = true })
vim.keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, buffer = true })

