-- Neovim configuration
-- ===================

-- Leader key (must be set before lazy.nvim loads plugins)
vim.g.mapleader = " "

-- Plugin manager (lazy.nvim)
-- --------------------------

-- Bootstrap lazy.nvim if it isn't installed yet
local LAZY_PATH = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(LAZY_PATH) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    LAZY_PATH,
  })
end
vim.opt.rtp:prepend(LAZY_PATH)

-- Plugin declarations
require("lazy").setup({
  -- Seamless Ctrl+h/j/k/l navigation between Neovim splits and Zellij panes
  {
    "fresh2dev/zellij.vim",
    lazy = false,
  },

  -- Color scheme
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    opts = {
      flavour = "mocha",
      transparent_background = true,
    },
  },

  -- Treesitter: language-aware syntax highlighting and text objects
  {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    build = function()
      -- Only install/update parsers when the plugin is installed or updated
      local parsers = {
        "python", "markdown", "markdown_inline", "rust", "typescript",
        "tsx", "javascript", "powershell", "lua", "bash", "json",
        "yaml", "toml",
      }
      require("nvim-treesitter").install(parsers)
    end,
    config = function()
      -- Enable treesitter highlighting for all filetypes that have a parser
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(args)
          pcall(vim.treesitter.start, args.buf)
        end,
        desc = "Enable treesitter highlighting",
      })
    end,
  },

  -- Git change markers in the sign column (loads when a file is opened)
  {
    "lewis6991/gitsigns.nvim",
    event = "BufReadPost",
    config = function()
      require("gitsigns").setup()
    end,
  },

  -- Informative status line (loads after initial render so it doesn't block startup)
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    dependencies = { "catppuccin" },
    config = function()
      require("lualine").setup({
        options = { theme = "catppuccin-nvim" },
      })
    end,
  },

  -- LSP server definitions (provides configs for vim.lsp.config)
  {
    "neovim/nvim-lspconfig",
    lazy = false,
  },

  -- Markdown rendering: pretty headings, tables, checkboxes in the buffer
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown", "markdown.mdx" },
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
    },
    keys = {
      { "<leader>md", "<cmd>RenderMarkdown toggle<CR>", desc = "Toggle markdown rendering" },
    },
    opts = {},
  },

  -- Fuzzy finder for files, grep, buffers, and more
  {
    "nvim-telescope/telescope.nvim",
    branch = "master",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<CR>", desc = "Find files" },
      { "<leader>fg", "<cmd>Telescope live_grep<CR>", desc = "Live grep" },
      { "<leader>fb", "<cmd>Telescope buffers<CR>", desc = "Find buffers" },
      { "<leader>fh", "<cmd>Telescope help_tags<CR>", desc = "Search help" },
      { "<leader>fd", "<cmd>Telescope diagnostics<CR>", desc = "Find diagnostics" },
      { "<leader>ft", "<cmd>TodoTelescope<CR>", desc = "Find TODOs" },
    },
    opts = {
      defaults = {
        -- Use fd for file finding (faster than the default find)
        find_command = { "fd", "--type", "f", "--strip-cwd-prefix" },
      },
    },
  },

  -- Fast cursor movement: press s + 2 chars to jump anywhere on screen
  {
    "folke/flash.nvim",
    opts = {},
    keys = {
      { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash jump" },
      { "S", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash treesitter select" },
    },
  },

  -- Highlight and search TODO/FIXME/HACK comments in code
  {
    "folke/todo-comments.nvim",
    event = "BufReadPost",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {},
  },

  -- Popup keybinding cheat sheet: pause after <leader> to see available keys
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    config = function()
      local wk = require("which-key")
      wk.setup()
      -- Register group labels so the popup shows descriptive names
      wk.add({
        { "<leader>f", group = "find" },
        { "<leader>m", group = "markdown" },
      })
    end,
  },

  -- Autocomplete engine (loads when entering insert mode)
  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
    },
    config = function()
      local cmp = require("cmp")
      cmp.setup({
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "buffer" },
          { name = "path" },
        }),
        -- preset.insert includes C-n/C-p to cycle, C-y to confirm, C-e to dismiss
        mapping = cmp.mapping.preset.insert({
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<CR>"] = cmp.mapping.confirm({ select = false }),
        }),
      })
    end,
  },
})

-- LSP
-- ---

-- Wire autocomplete capabilities into pyright and enable it
vim.lsp.config("pyright", {
  capabilities = vim.lsp.protocol.make_client_capabilities(),
})
vim.lsp.enable("pyright")

-- Override gd to use LSP go-to-definition when a language server is attached
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    vim.keymap.set("n", "gd", vim.lsp.buf.definition, {
      buffer = args.buf,
      desc = "LSP go to definition",
    })
  end,
  desc = "Set LSP keymaps on attach",
})

-- Merge in cmp capabilities once nvim-cmp loads
vim.api.nvim_create_autocmd("User", {
  pattern = "LazyLoad",
  callback = function(args)
    if args.data == "cmp-nvim-lsp" then
      vim.lsp.config("pyright", {
        capabilities = require("cmp_nvim_lsp").default_capabilities(),
      })
    end
  end,
  desc = "Update LSP capabilities when cmp loads",
})

-- Display
-- -------

-- Enable 24-bit RGB color in the terminal
vim.opt.termguicolors = true

-- Use Catppuccin Mocha color scheme (transparency handled by plugin opts above)
vim.cmd.colorscheme("catppuccin")

-- Show line numbers
vim.opt.number = true
vim.opt.relativenumber = false

-- Highlight the line the cursor is on
vim.opt.cursorline = true

-- Always show the sign column so the editor doesn't shift when diagnostics appear
vim.opt.signcolumn = "yes"

-- Keep some lines visible above/below the cursor when scrolling
local SCROLL_MARGIN = 8
vim.opt.scrolloff = SCROLL_MARGIN
vim.opt.sidescrolloff = SCROLL_MARGIN

-- Indentation
-- -----------

local INDENT_WIDTH = 4
vim.opt.tabstop = INDENT_WIDTH
vim.opt.shiftwidth = INDENT_WIDTH
vim.opt.softtabstop = INDENT_WIDTH
vim.opt.expandtab = true
vim.opt.smartindent = true

-- Search
-- ------

-- Case-insensitive search unless the query contains uppercase letters
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- Highlight all matches while searching, clear with :noh
vim.opt.hlsearch = true
vim.opt.incsearch = true

-- Splits
-- ------

-- New splits open to the right and below (more natural)
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Files and undo
-- --------------

-- Persist undo history across sessions
vim.opt.undofile = true

-- Disable swap files (saves are frequent enough, and swap causes nuisances)
vim.opt.swapfile = false

-- Faster update time for CursorHold events and swap writes
local UPDATE_DELAY_MS = 250
vim.opt.updatetime = UPDATE_DELAY_MS

-- Interaction
-- -----------

-- Enable mouse only for scroll wheel support
vim.opt.mouse = "a"

-- Disable all mouse actions except the scroll wheel
local mouse_events = {
  "<LeftMouse>", "<LeftDrag>", "<LeftRelease>",
  "<2-LeftMouse>", "<3-LeftMouse>", "<4-LeftMouse>",
  "<RightMouse>", "<RightDrag>", "<RightRelease>",
  "<2-RightMouse>",
  "<MiddleMouse>", "<MiddleDrag>", "<MiddleRelease>",
  "<2-MiddleMouse>",
}
for _, event in ipairs(mouse_events) do
  vim.keymap.set({"n", "v", "i", "c"}, event, "", { noremap = true })
end

-- Remove the right-click popup menu entirely
vim.cmd([[aunmenu PopUp]])
vim.cmd([[autocmd! nvim.popupmenu]])

-- VS Code-like scrolling: scroll wheel moves the viewport, hjkl moves the cursor
local SCROLL_SPEED = 3
vim.keymap.set({"n", "v", "i"}, "<ScrollWheelUp>",   SCROLL_SPEED .. "<C-y>", { noremap = true, desc = "Scroll viewport up" })
vim.keymap.set({"n", "v", "i"}, "<ScrollWheelDown>", SCROLL_SPEED .. "<C-e>", { noremap = true, desc = "Scroll viewport down" })

-- Smooth sub-line scrolling on wrapped lines (Neovim 0.10+)
vim.opt.smoothscroll = true

-- Use the system clipboard for yank/paste
vim.opt.clipboard = "unnamedplus"

-- Show matching bracket briefly when inserting one
vim.opt.showmatch = true

-- Ignore Shift+F15 (external keep-alive script sends this periodically)
vim.keymap.set({"n", "v", "i", "c", "t"}, "<S-F15>", "", { noremap = true })

-- Wrapping and formatting
-- -----------------------

-- Don't wrap long lines by default
vim.opt.wrap = false

-- When wrap is enabled (e.g. for prose), break at word boundaries
vim.opt.linebreak = true

-- Whitespace visibility: show tabs and trailing spaces
vim.opt.list = true
vim.opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }

-- Treesitter / Markdown
-- ---------------------

-- nvim-treesitter handles syntax highlighting for all configured languages.
-- This autocmd just enables soft wrap for markdown since that's a display
-- preference, not something treesitter manages.
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "markdown.mdx" },
  callback = function(args)
    vim.schedule(function()
      for _, win in ipairs(vim.fn.win_findbuf(args.buf)) do
        vim.api.nvim_set_option_value("wrap", true, { win = win })
      end
    end)
  end,
  desc = "Enable soft wrap for markdown files",
})

-- Quality-of-life autocommands
-- ----------------------------

-- Briefly flash yanked text so you can see what was copied
local YANK_HIGHLIGHT_MS = 200
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function()
    vim.highlight.on_yank({ timeout = YANK_HIGHLIGHT_MS })
  end,
  desc = "Highlight yanked text",
})

-- Restore cursor position when reopening a file
vim.api.nvim_create_autocmd("BufReadPost", {
  callback = function(args)
    local mark = vim.api.nvim_buf_get_mark(args.buf, '"')
    local line_count = vim.api.nvim_buf_line_count(args.buf)
    if mark[1] > 0 and mark[1] <= line_count then
      vim.api.nvim_win_set_cursor(0, mark)
    end
  end,
  desc = "Jump to last cursor position on file open",
})

-- Strip trailing whitespace before saving
vim.api.nvim_create_autocmd("BufWritePre", {
  callback = function()
    local view = vim.fn.winsaveview()
    vim.cmd([[silent! %s/\s\+$//e]])
    vim.fn.winrestview(view)
  end,
  desc = "Remove trailing whitespace on save",
})
