local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- Hosts and usernames live in a private, uncommitted file next to this one
-- (copy wezterm_private.example.lua to wezterm_private.lua)
local private = dofile(wezterm.config_dir .. '/wezterm_private.lua')

-- Change tab title to show the current working directory instead of the default "user@host:dir"
wezterm.on('format-tab-title', function(tab)
  local pane = tab.active_pane
  local cwd = pane.current_working_dir
  local title = pane.title

  if cwd then
    -- Newer WezTerm returns a Url object, older versions a "file://host/path" string
    local path = type(cwd) == 'userdata' and cwd.file_path
                 or tostring(cwd):gsub('^file://[^/]*', '')
    path = path:gsub('^/home/[^/]+', '~')   -- shorten home to ~
    title = path:match('([^/]+)/?$') or path -- keep only the last folder
  end

  return ' ' .. (tab.tab_index + 1) .. ': ' .. title .. ' '
end)

-- SSH domains for remote hosts
config.ssh_domains = private.ssh_domains

-- Launching WezTerm connects straight to the default server
config.default_gui_startup_args = { 'connect', private.default_domain }

-- The tab bar
config.window_frame = {
  -- The font used in the tab bar.
  font = wezterm.font { family = 'Roboto', weight = 'Medium' },
  -- The size of the font in the tab bar. Default to 10.0 on Windows
  font_size = 12.0,
}

-- window bar
config.window_decorations = "RESIZE"

-- paste image from clipboard to remote host
config.keys = {
  { key = 'v', mods = 'CTRL|ALT', action = wezterm.action_callback(function(window, pane)
      local function fail(msg, err)
        wezterm.log_error('clip paste: ' .. msg .. ' ' .. (err or ''))
        window:toast_notification('Image paste', msg, nil, 4000)
      end
      wezterm.log_info('clip paste: triggered')
      -- Upload to the host of the focused pane; domain names equal their SSH hosts
      local host = pane:get_domain_name()
      local is_ssh = false
      for _, d in ipairs(config.ssh_domains) do
        if d.name == host then is_ssh = true end
      end
      if not is_ssh then return fail('Pane is not on an SSH domain (' .. host .. ')') end
      local name = 'clip-' .. os.time() .. '.png'
      local tmp = os.getenv('TEMP') .. '\\' .. name
      local ok, _, err = wezterm.run_child_process({ 'powershell.exe', '-NoProfile', '-Command',
        "Add-Type -AssemblyName System.Windows.Forms; $i=[Windows.Forms.Clipboard]::GetImage(); " ..
        "if(-not $i){exit 1}; $i.Save('" .. tmp .. "',[Drawing.Imaging.ImageFormat]::Png)" })
      if not ok then return fail('No image on the clipboard', err) end
      -- Relative to the remote home dir, so it works on Linux (/home) and macOS (/Users);
      -- scp resolves a relative remote path against home, the shell resolves ~
      local dest = '.cache/clip/' .. name
      ok, _, err = wezterm.run_child_process({ 'scp', '-o', 'BatchMode=yes', tmp, host .. ':' .. dest })
      os.remove(tmp)
      if not ok then return fail('scp to ' .. host .. ' failed', err) end
      pane:send_text('~/' .. dest .. ' ')
  end) },
}

return config
