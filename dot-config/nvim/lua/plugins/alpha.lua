return {
	"goolord/alpha-nvim",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-tree/nvim-web-devicons",
	},
	config = function()
		local alpha = require("alpha")
		local dashboard = require("alpha.themes.dashboard")
		local theta = require("alpha.themes.theta")

		local function wrap_quote(quote, max_width)
			local wrapped = {}
			local line = ""
			for word in quote:gmatch("%S+") do
				if #line + #word + 1 > max_width then
					table.insert(wrapped, line)
					line = word
				else
					line = #line == 0 and word or (line .. " " .. word)
				end
			end
			if #line > 0 then
				table.insert(wrapped, line)
			end
			return table.concat(wrapped, "\n")
		end

		local function get_quote()
			local quotes = {
				"A year from now will you look back and say you could have done more? - Alex Hormozi",
				"When you make enough money on the backend, you can be silly on the front end. - Alex Hormozi",
				"Unspoken expectations are premeditated resentments. - Brene Brown",
				"You’d be amazed how hard it is to beat a man who shows up on time and does what they said they were gonna do the first time. - Alex Hormozi",
				"The biggest risk to your future isn’t your competition, it’s the distractions you insist on keeping in your life rather than doing the things you know you should be doing but aren’t. - Alex Hormozi",
			}

			return wrap_quote(quotes[math.random(#quotes)], 85)
		end

		local logo = [[



 _________  ______    ______    _______   ______    ______   ______   ___   ___
/________/\/_____/\  /_____/\ /_______/\ /_____/\  /_____/\ /_____/\ /___/\/__/\
\__.::.__\/\:::_ \ \ \:::_ \ \\::: _  \ \\:::_ \ \ \:::_ \ \\:::__\/ \::.\ \\ \ \
   \::\ \   \:(_) ) )_\:\ \ \ \\::(_)  \/_\:(_) ) )_\:\ \ \ \\:\ \  __\:: \/_) \ \
    \::\ \   \: __ `\ \\:\ \ \ \\::  _  \ \\: __ `\ \\:\ \ \ \\:\ \/_/\\:. __  ( (
     \::\ \   \ \ `\ \ \\:\_\ \ \\::(_)  \ \\ \ `\ \ \\:\_\ \ \\:\_\ \ \\: \ )  \ \
      \__\/    \_\/ \_\/ \_____\/ \_______\/ \_\/ \_\/ \_____\/ \_____\/ \__\/\__\/



]]

		logo = logo .. get_quote() .. "\n"
		theta.header.val = vim.split(logo, "\n", { trimempty = false })

		theta.buttons.val = {
			{ type = "text", val = "Quick links", opts = { hl = "SpecialComment", position = "center" } },
			{ type = "padding", val = 1 },
			dashboard.button("e", "  New file", "<cmd>ene<CR>"),
			dashboard.button("s", "  Restore Session", [[<cmd> lua require("persistence").load() <cr>]]),
			dashboard.button("c", "  Configuration", "<cmd>cd ~/.config/nvim/ <CR>"),
			dashboard.button("u", "  Update plugins", "<cmd>Lazy sync<CR>"),
			dashboard.button("q", "󰅚  Quit", "<cmd>qa<CR>"),
		}

		dashboard.section.footer.val = get_quote()

		alpha.setup(theta.config)
	end,
}
