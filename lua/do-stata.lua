local M = {}

-- Global variable to track if Stata has been opened this session
M.stata_opened = false

---@class Config
---@field stata_ver "StataBE" | "StataSE" | "StataMP"
M.config = {
  stata_ver = "StataMP",
  cell_delimiter = "//%%"
}

M.get_text = function()
  local function is_vmode()
    local mode = vim.api.nvim_get_mode().mode
    return mode == 'v' or mode == 'V'
  end

  local line_start = 0
  local line_end = vim.api.nvim_buf_line_count(0)
  local esc = vim.api.nvim_replace_termcodes('<esc>', true, false, true)
  local text = ''

  if is_vmode() then
    vim.api.nvim_feedkeys(esc, 'x', false)
    line_start = vim.fn.getpos("'<")[2] - 1
    line_end = vim.fn.getpos("'>")[2]
  end

  local lines = vim.api.nvim_buf_get_lines(0, line_start, line_end, false)
  return table.concat(lines, '\n')
end

M.save_file = function(text, filename)
  local file = io.open(filename, "w")
  if file then
    file:write(text)
    file:close()
  end
end

M.get_selected_text_or_word = function()
  local mode = vim.api.nvim_get_mode().mode
  if mode == 'v' or mode == 'V' then
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    if start_pos == nil or end_pos == nil then
      print("Error: Unable to get selection positions")
      return ""
    end
    local lines = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, end_pos[2], false)
    if #lines == 0 then
      print("Error: No lines in selection")
      return ""
    end
    if #lines == 1 then
      return lines[1]:sub(start_pos[3], end_pos[3])
    else
      lines[1] = lines[1]:sub(start_pos[3])
      lines[#lines] = lines[#lines]:sub(1, end_pos[3])
      return table.concat(lines, "\n")
    end
  else
    local word = vim.fn.expand("<cword>")
    return word ~= nil and word or ""
  end
end

M.ensure_stata_running = function()
  if not M.stata_opened then
    local is_running = vim.fn.system('pgrep -q "' .. M.config.stata_ver .. '"; echo $?')
    if tonumber(is_running) ~= 0 then
      vim.fn.system('open -a "' .. M.config.stata_ver .. '"')
    end
    M.stata_opened = true
  end
end

M.run_do = function(filename)
  M.ensure_stata_running()

  local output = vim.fn.system {
    'osascript',
    '-e',
    string.format('tell application \"%s\"', M.config.stata_ver),
    '-e',
    string.format('DoCommandAsync \"do %s\"', filename),
    '-e',
    'end tell'
  }

  if string.sub(output, 1, 1) ~= '0' then
    print('Error executing Stata!')
  end
end

M.execute_cell = function()
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local cell_start, cell_end = current_line, current_line

  while cell_start > 1 and not lines[cell_start-1]:match("^" .. M.config.cell_delimiter) do
    cell_start = cell_start - 1
  end
  while cell_end < #lines and not lines[cell_end+1]:match("^" .. M.config.cell_delimiter) do
    cell_end = cell_end + 1
  end

  local cell_text = table.concat(vim.api.nvim_buf_get_lines(0, cell_start-1, cell_end, false), '\n')
  local tempname = string.format('%s.do', vim.fn.tempname())
  M.save_file(cell_text, tempname)
  M.run_do(tempname)
end

M.show_help = function()
  local selected_text = M.get_selected_text_or_word()
  local help_command = string.format('help %s', selected_text)
  M.run_do(help_command)
end

M.show_data_browser = function()
  local selected_vars = M.get_selected_text_or_word()
  local browse_command = string.format('browse %s', selected_vars)
  M.run_do(browse_command)
end

M.run_whole_file = function()
  local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  local tempname = string.format('%s.do', vim.fn.tempname())
  M.save_file(text, tempname)
  M.run_do(tempname)
end

M.run_line = function()
  local tempname = string.format('%s.do', vim.fn.tempname())
  local text = M.get_text()
  M.save_file(text, tempname)
  M.run_do(tempname)
end

M.run_up_to_line = function()
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, 0, current_line, false)
  local text = table.concat(lines, '\n')
  
  local tempname = string.format('%s.do', vim.fn.tempname())
  M.save_file(text, tempname)
  M.run_do(tempname)
end

M.send_to_stata_command = function()
  local selected_text = M.get_selected_text_or_word()
  M.ensure_stata_running()

  local output = vim.fn.system {
    'osascript',
    '-e',
    string.format('tell application \"%s\"', M.config.stata_ver),
    '-e',
    string.format('DoCommandAsync \"%s\"', selected_text:gsub('"', '\\"')),
    '-e',
    'end tell'
  }

  if string.sub(output, 1, 1) ~= '0' then
    print('Error sending command to Stata!')
  end
end

M.setup = function(opts)
  local map = vim.keymap.set

  M.config = vim.tbl_extend("force", M.config, opts or {})

  vim.api.nvim_create_user_command("DoStata", function()
    require("do-stata").run_line()
  end, { nargs = '*', desc = "Run do file in Stata" })
  
  vim.api.nvim_create_user_command("DoStataFile", function()
    require("do-stata").run_whole_file()
  end, { nargs = 0, desc = "Run entire file in Stata" })

  vim.api.nvim_create_user_command("DoStataUpToLine", function()
    require("do-stata").run_up_to_line()
  end, { nargs = 0, desc = "Run Stata code up to current line" })

  vim.api.nvim_create_user_command("SendToStataCommand", function()
    require("do-stata").send_to_stata_command()
  end, { nargs = 0, desc = "Send selected text to Stata command window" })

  map("n", "<leader>s", "<cmd>SendToStataCommand<cr>")
  map("v", "<leader>s", "<cmd>SendToStataCommand<cr>")

  map("n", "<leader>r", "<cmd>DoStata<cr>")
  map("v", "<leader>r", "<cmd>DoStata<cr>")
  map("n", "<leader>R", "<cmd>DoStataFile<cr>")
  map("n", "<leader>u", "<cmd>DoStataUpToLine<cr>")  -- New mapping for run_up_to_line
  map("n", "<F1>", M.show_help)
  map("v", "<F1>", M.show_help)
  map("n", "<F2>", M.show_data_browser)
  map("v", "<F2>", M.show_data_browser)
  map("n", "<leader>e", M.execute_cell)
end

return {
  setup = M.setup,
  run_line = M.run_line,
  run_whole_file = M.run_whole_file,
  run_up_to_line = M.run_up_to_line,  -- Add new function to the returned table
  show_help = M.show_help,
  show_data_browser = M.show_data_browser,
  execute_cell = M.execute_cell,
  send_to_stata_command = M.send_to_stata_command,
  config = M.config
}



    -- keys = {
    --   { "<leader>r", "<cmd>DoStata<cr>", desc = "Run Stata code" },
    --   { "<F1>", function() require("do-stata").show_help() end, desc = "Show Stata help" },
    --   { "<F2>", function() require("do-stata").show_data_browser() end, desc = "Show Stata data browser" },
    --   { "<leader>F", function() require("do-stata").execute_cell() end, desc = "Execute Stata cell" },
    -- },
    -- cmd = { "DoStata", "DoStataFile" },
