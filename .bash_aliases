# ~/.bash_aliases: aliases and small helper functions, sourced by ~/.bashrc.

## LS AND GREP ##

if [ -x /usr/bin/dircolors ]; then
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
fi

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

## TERMINAL ##

# Set the terminal title; defaults to "folder (branch)"
tabname() {
    local name="$*"
    if [ -z "$name" ]; then
        name="$(basename "$PWD")"
        local branch
        branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
        [ "$branch" = "HEAD" ] && branch="$(git rev-parse --short HEAD 2>/dev/null)"
        [ -n "$branch" ] && name="$name ($branch)"
    fi
    printf '\033]0;%s\007' "$name"
}

## GIT ##

# Prune merged worktrees, then delete local branches whose remote branch is gone
alias git-remove-untracked='wt step prune --min-age=0s; git fetch --prune && git branch -r | awk "{print \$1}" | egrep -v -f /dev/fd/0 <(git branch -vv | grep origin) | awk "{print \$1}" | xargs git branch -d'

alias git-log='git log --pretty="%C(Yellow)%h  %C(reset)%ad%x09%C(Cyan)[%<(8,trunc)%aN] %C(reset)%s" --date=relative'
alias git-log-no-merges='git log --pretty="%C(Yellow)%h  %C(reset)%ad%x09%C(Cyan)[%<(8,trunc)%aN] %C(reset)%s" --date=relative --no-merges'
alias git-log-no-pager='git --no-pager log --pretty="%C(Yellow)%h  %C(reset)%ad%x09%C(Cyan)[%<(8,trunc)%aN] %C(reset)%s" --date=relative'

# Commits in from_branch (default: current) that are not in to_branch (default: origin/master)
function git-log-diff() {
    to_branch=$1
    from_branch=$2
    if [ -z $to_branch ]; then
        to_branch='origin/master'
    fi
    if [ -z $from_branch ]; then
        from_branch=`git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/'`
    fi
    branches=$to_branch..$from_branch
    echo "git --no-pager log $branches --pretty=\"%C(Yellow)%h  %C(reset)%ad%x09%C(Cyan)[%<(9,trunc)%aN] %C(reset)%s\" --date=relative"
    git --no-pager log $branches --pretty="%C(Yellow)%h  %C(reset)%ad%x09%C(Cyan)[%<(9,trunc)%aN] %C(reset)%s" --date=relative
}

## WORKTRUNK ##

alias wt-prune='wt step prune --min-age=0s'
alias wsc='wt switch --base @ --create --execute=claude'
alias wsx='wt switch --base @ --create --execute=codex'

## CODING AGENTS ##

alias cld='claude -c || claude'
alias cdx='codex resume --last'
alias cldp='MAX_THINKING_TOKENS=0 claude -p --settings '\''{}'\'' --no-session-persistence --model=haiku --effort low'
alias cdxp='codex e --ephemeral -c model_reasoning_effort=low 2>/dev/null'

alias commit='MAX_THINKING_TOKENS=0 claude -p --setting-sources user --strict-mcp-config --settings '\''{"disableAllHooks": true}'\'' --no-session-persistence --model=haiku --effort low "/commit"'
alias commitx='codex e --ephemeral -c model_reasoning_effort=low /commit 2>/dev/null'

pr-review() { claude "/code-review PR $1"; }

## AWS ##

alias aws-login='aws sso login --profile common'

## KUBERNETES ##

# Show the current namespace, or switch to the given one
function kubectl-namespace() {
    namespace=$1
    if [ -z $namespace ]; then
        echo "current namespace: `kubectl config view --minify --output 'jsonpath={..namespace}'`"
        return 0
    fi
    kubectl config set-context $(kubectl config current-context) --namespace $namespace
}

alias k8='kubectl'
alias k8-ns='kubectl-namespace'
alias kpods='kubectl get pods'
alias ksvc='kubectl get svc'
alias kservices='kubectl get services'
alias kdesc='kubectl describe pod'
alias kdel='kubectl delete pod'
alias klogs='kubectl logs -f --tail 250'

## MAVEN ##

# Write the project's dependency report to dependencies.md; overwrites ./dist
alias mvn-dependencies='mvn project-info-reports:dependencies && npx @wcj/html-to-markdown-cli target/reports/dependencies.html && mv dist/dependencies.html.md dependencies.md && rm -rf dist/'

## DOCKER ##

alias docker-prune='docker network prune -f && docker image prune --all --filter "until=240h"'
