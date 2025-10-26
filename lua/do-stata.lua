local M = {}

-- Global variable to track if Stata has been opened this session
M.stata_opened = false

---@class Config
---@field stata_ver "StataBE" | "StataSE" | "StataMP"
M.config = {
  stata_ver = "StataMP",
  cell_delimiter = "//%%"
}

M.start_stata = function()
  if not M.stata_opened then
    vim.fn.system('open -a "' .. M.config.stata_ver .. '"')
    M.stata_opened = true
    print("Stata started!")
  else
    print("Stata is already running!")
  end
end

M.quit_stata = function()
  if M.stata_opened then
    vim.fn.system {
      'osascript',
      '-e',
      string.format('tell application \"%s\"', M.config.stata_ver),
      '-e',
      'quit',
      '-e',
      'end tell'
    }
    M.stata_opened = false
    print("Stata closed!")
  else
    print("Stata is not running!")
  end
end

M.clear_memory = function(clear_type)
  local command
  if clear_type == "all" then
    command = "clear all"
  elseif clear_type == "matrix" then
    command = "clear matrix"
  elseif clear_type == "results" then
    command = "clear results"
  elseif clear_type == "programs" then
    command = "clear programs"
  else
    command = "clear"
  end

  local output = vim.fn.system {
    'osascript',
    '-e',
    string.format('tell application \"%s\"', M.config.stata_ver),
    '-e',
    string.format('DoCommandAsync \"%s\"', command),
    '-e',
    'end tell'
  }
  print("Stata " .. command .. " executed!")
end

M.set_working_directory = function()
  local current_file = vim.fn.expand('%:p:h')
  local command = string.format('cd "%s"', current_file)
  
  local output = vim.fn.system {
    'osascript',
    '-e',
    string.format('tell application \"%s\"', M.config.stata_ver),
    '-e',
    string.format('DoCommandAsync \"%s\"', command),
    '-e',
    'end tell'
  }
  print("Working directory set to: " .. current_file)
end

M.describe_variables = function()
  local selected_vars = M.get_selected_text_or_word()
  local command
  if selected_vars ~= "" then
    command = "describe " .. selected_vars
  else
    command = "describe"
  end

  local output = vim.fn.system {
    'osascript',
    '-e',
    string.format('tell application \"%s\"', M.config.stata_ver),
    '-e',
    string.format('DoCommandAsync \"%s\"', command),
    '-e',
    'end tell'
  }
end

-- Function to summarize variables
M.summarize_variables = function()
  local selected_vars = M.get_selected_text_or_word()
  local command
  if selected_vars ~= "" then
    command = "summarize " .. selected_vars
  else
    command = "summarize"
  end

  local output = vim.fn.system {
    'osascript',
    '-e',
    string.format('tell application \"%s\"', M.config.stata_ver),
    '-e',
    string.format('DoCommandAsync \"%s\"', command),
    '-e',
    'end tell'
  }
end

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
  local command = "help " .. selected_text

  local output = vim.fn.system {
    'osascript',
    '-e',
    string.format('tell application \"%s\"', M.config.stata_ver),
    '-e',
    string.format('DoCommandAsync \"%s\"', command),
    '-e',
    'end tell'
  }
end

M.show_data_browser = function()
  local selected_vars = M.get_selected_text_or_word()
  local command
  if selected_vars ~= "" then
    command = "browse " .. selected_vars
  else
    command = "browse"
  end

  local output = vim.fn.system {
    'osascript',
    '-e',
    string.format('tell application \"%s\"', M.config.stata_ver),
    '-e',
    string.format('DoCommandAsync \"%s\"', command),
    '-e',
    'end tell'
  }
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

M.setup = function(opts)
  M.config = vim.tbl_extend("force", M.config, opts or {})

  -- user commands are fine to define globally
  vim.api.nvim_create_user_command("DoStata", function()
    require("do-stata").run_line()
  end, { nargs = '*', desc = "Run do file in Stata" })
  
  vim.api.nvim_create_user_command("DoStataFile", function()
    require("do-stata").run_whole_file()
  end, { nargs = 0, desc = "Run entire file in Stata" })

  vim.api.nvim_create_user_command("DoStataUpToLine", function()
    require("do-stata").run_up_to_line()
  end, { nargs = 0, desc = "Run Stata code up to current line" })

  -- define mappings only for stata buffers
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "stata",
    callback = function(args)
      local map = function(mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { buffer = args.buf, noremap = true, silent = true, desc = desc })
      end
      map("n", "<leader>ss", M.start_stata, "Start Stata")
      map("n", "<leader>sq", M.quit_stata, "Quit Stata")
      map("n", "<leader>sc", M.clear_memory, "Clear Memory")
      map("n", "<leader>sw", M.set_working_directory, "Set Working Directory")
      map("n", "<leader>sv", M.describe_variables, "Describe Variables")
      map("n", "<leader>sm", M.summarize_variables, "Summarize Variables")
      map("n", "<leader>sd", "<cmd>DoStata<cr>", "Run Stata Command")
      map("v", "<leader>sd", "<cmd>DoStata<cr>", "Run Stata Command (Visual)")
      map("n", "<leader>sr", "<cmd>DoStataFile<cr>", "Run Stata File")
      map("n", "<leader>su", "<cmd>DoStataUpToLine<cr>", "Run Up to Line")
      map("n", "<F1>", M.show_help, "Show Help")
      map("v", "<F1>", M.show_help, "Show Help (Visual)")
      map("n", "<F2>", M.show_data_browser, "Show Data Browser")
      map("v", "<F2>", M.show_data_browser, "Show Data Browser (Visual)")
      map("n", "<leader>se", M.execute_cell, "Execute Cell")
    end,
  })
end

return {
  setup = M.setup,
  quit_stata = M.quit_stata,
  clear_memory = M.clear_memory,
  set_working_directory = M.set_working_directory,
  describe_variables = M.describe_variables,
  summarize_variables = M.summarize_variables,
  run_line = M.run_line,
  run_whole_file = M.run_whole_file,
  run_up_to_line = M.run_up_to_line,
  show_help = M.show_help,
  show_data_browser = M.show_data_browser,
  execute_cell = M.execute_cell,
  start_stata = M.start_stata,  -- Add the new function to the returned table
  config = M.config
}
