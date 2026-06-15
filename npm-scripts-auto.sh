#!/bin/zsh

# Configuration
# If PACKAGE_MANAGER is not set, it is auto-detected from lockfiles.
PACKAGE_MANAGER=${PACKAGE_MANAGER:-""}
NPM_SCRIPTS_AUTO_VERBOSE=${NPM_SCRIPTS_AUTO_VERBOSE:-0}

# Autoload hooks
autoload -U add-zsh-hook
zmodload zsh/stat 2>/dev/null || true

# Associative array to track dynamically created commands
typeset -A _npm_script_cmds
typeset _npm_scripts_loaded_sig=""

_npm_scripts_detect_package_manager() {
    if [[ -n "$PACKAGE_MANAGER" ]]; then
        echo "$PACKAGE_MANAGER"
        return
    fi

    if [[ -f package-lock.json ]]; then
        echo "npm"
    elif [[ -f yarn.lock ]]; then
        echo "yarn"
    elif [[ -f pnpm-lock.yaml ]]; then
        echo "pnpm"
    else
        echo "npm"
    fi
}

# Function to show interactive script selection
scripts() {
    if [[ ! -f package.json ]]; then
        echo "❌ No package.json found in current directory"
        return 1
    fi

    local package_manager
    package_manager=$(_npm_scripts_detect_package_manager)

    local scripts
    scripts=("${(@f)$(jq -r '.scripts | keys[]' package.json 2>/dev/null)}")

    if [[ ${#scripts[@]} -eq 0 ]]; then
        echo "❌ No scripts found in package.json"
        return 1
    fi

    echo "📦 Available ${package_manager} scripts:"
    echo "Type script name or number to run. \n"

    PS3=$'\nSelect a script to run: '
    select script in "${scripts[@]}" "Cancel"; do
        case $script in
            "Cancel")
                echo "Operation cancelled"
                return 0
                ;;
            *)
                # Check if input is a number or script name
                if [[ -n $script ]]; then
                    # Number was selected from menu
                    echo "\nRunning: ${package_manager} run $script\n"
                    $package_manager run $script
                    return 0
                elif [[ " ${scripts[@]} " =~ " $REPLY " ]]; then
                    # Script name was typed directly
                    echo "\nRunning: ${package_manager} run $REPLY\n"
                    $package_manager run $REPLY
                    return 0
                else
                    echo "Invalid selection. Please try again."
                fi
                ;;
        esac
    done
}

# Function to generate completions for a command
_generate_npm_script_completion() {
    local cmd=$1
    eval "_${cmd}_completion() {
        local -a commands
        commands=(\${(@k)_npm_script_cmds})
        _describe 'command' commands
    }"
    compdef "_${cmd}_completion" "$cmd"
}

# Clear dynamically generated functions and completion handlers
_npm_scripts_clear_dynamic_commands() {
    for cmd in "${(@k)_npm_script_cmds}"; do
        unfunction "$cmd" 2>/dev/null
        unfunction "_${cmd}_completion" 2>/dev/null
    done
    _npm_script_cmds=()
}

_npm_scripts_package_signature() {
    [[ -f package.json ]] || return 1

    local mtime
    local size

    if zstat -H stat +mtime +size -- package.json 2>/dev/null; then
        mtime=$stat[mtime]
        size=$stat[size]
    else
        mtime=$(stat -f %m package.json 2>/dev/null || stat -c %Y package.json 2>/dev/null)
        size=$(stat -f %z package.json 2>/dev/null || stat -c %s package.json 2>/dev/null)
    fi

    echo "${PWD}:${mtime}:${size}"
}

_npm_scripts_apply_scripts() {
    _npm_scripts_clear_dynamic_commands

    local script
    for script in "$@"; do
        eval "function $script() { local package_manager; package_manager=\$(_npm_scripts_detect_package_manager); \$package_manager run $script \"\$@\" }"
        _npm_script_cmds[$script]=1
        _generate_npm_script_completion "$script"
    done

    if [[ $# -gt 0 && "$NPM_SCRIPTS_AUTO_VERBOSE" == "1" ]]; then
        local package_manager
        package_manager=$(_npm_scripts_detect_package_manager)
        echo "⚡ ${package_manager} scripts loaded. Type 'scripts' to view all."
    fi
}

# Parse package.json scripts and register commands.
_npm_scripts_start_async_update() {
    if [[ ! -f package.json ]]; then
        _npm_scripts_loaded_sig=""
        _npm_scripts_clear_dynamic_commands
        return
    fi

    local sig
    sig=$(_npm_scripts_package_signature) || return

    if [[ "$sig" == "$_npm_scripts_loaded_sig" ]]; then
        return
    fi

    local scripts
    scripts=("${(@f)$(jq -r '.scripts | keys[]' package.json 2>/dev/null)}")

    _npm_scripts_apply_scripts "${scripts[@]}"
    _npm_scripts_loaded_sig="$sig"
}

# Removed from hooks when re-sourcing shells that loaded older async versions.
_npm_scripts_poll_async_update() {
    return 0
}

# Hooks
add-zsh-hook chpwd _npm_scripts_start_async_update
add-zsh-hook -d precmd _npm_scripts_poll_async_update 2>/dev/null || true

# Trigger parse on shell startup
_npm_scripts_start_async_update
