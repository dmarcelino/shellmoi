-- Copy to wezterm_private.lua and fill in your own hosts and usernames.
-- Domain names must equal their SSH hosts; the image paste relies on that.
local user = 'your-user'

return {
  -- Domain WezTerm connects to on startup
  default_domain = 'linux-box',

  ssh_domains = {
    {
      name = 'linux-box',
      remote_address = 'linux-box',   -- or host:port
      username = user,
      -- ssh_option = { identityfile = 'C:/Users/<you>/.ssh/id_ed25519' },
    },
    {
      name = 'mac-box',
      remote_address = 'mac-box',
      username = user,
      -- Non-interactive SSH on macOS has a bare PATH without the app or Homebrew
      remote_wezterm_path = '/Applications/WezTerm.app/Contents/MacOS/wezterm',
    },
  },
}
