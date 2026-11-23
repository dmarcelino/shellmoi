# ~/.bash_profile: executed by bash(1) for login shells (macOS terminals, ssh), instead of
# ~/.profile.

# Keep what ~/.profile sets up, as bash skips it when this file exists
if [ -f ~/.profile ]; then
    . ~/.profile
fi

# Debian and Ubuntu's ~/.profile already loads ~/.bashrc; don't load it twice
if [ -z "${SHELLMOI_BASHRC:-}" ] && [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi
