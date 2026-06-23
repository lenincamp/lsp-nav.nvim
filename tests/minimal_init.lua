vim.cmd("set rtp+=.")
vim.cmd("set rtp+=" .. vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim"))
vim.opt.swapfile = false
vim.opt.backup = false
