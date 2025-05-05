#!/usr/bin/env bash

# QBoss: Advanced KDE Window Manager
# A feature-rich TUI for KDE Wayland environments
# https://github.com/eraxe/qboss/
#
# Version: 1.1.0
# Author: QBoss Team
#
# Features:
# - Window listing, searching, and management
# - Copy window IDs, classes, and titles to clipboard
# - DBus service exploration
# - Window monitoring and properties capture
# - Custom qdbus command execution
# - Script generation for window interactions
# - App Helper for quick app launching and toggling

set -o errexit
set -o nounset
set -o pipefail

# Constants and global variables
readonly VERSION="1.1.0"
readonly GITHUB_REPO="eraxe/qboss"
readonly GITHUB_RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main/qboss.sh"
readonly APP_NAME="qboss"
readonly INSTALL_DIR="/usr/local/bin"
readonly COMPLETION_DIR="/etc/bash_completion.d"

# Configuration paths
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/${APP_NAME}"
readonly CONFIG_FILE="${CONFIG_DIR}/config.json"
readonly HISTORY_FILE="${CONFIG_DIR}/history.txt"
readonly THEMES_DIR="${CONFIG_DIR}/themes"
readonly PLUGINS_DIR="${CONFIG_DIR}/plugins"
readonly LOGS_DIR="${CONFIG_DIR}/logs"
readonly APPS_CONFIG_FILE="${CONFIG_DIR}/apps.json"

# Default settings
readonly DEFAULT_MAX_HISTORY=50
readonly DEFAULT_THEME="synthwave"
readonly DEFAULT_CLIPBOARD_TOOL="wl-copy"
readonly DEFAULT_NOTIFICATION=true
readonly DEFAULT_LOG_LEVEL="info"
readonly DEFAULT_COMPACT_VIEW=false

# Synthwave theme colors
readonly SW_MAGENTA='\033[38;5;206m'
readonly SW_CYAN='\033[38;5;51m'
readonly SW_BLUE='\033[38;5;39m'
readonly SW_PURPLE='\033[38;5;135m'
readonly SW_PINK='\033[38;5;213m'
readonly SW_YELLOW='\033[38;5;226m'
readonly SW_ORANGE='\033[38;5;208m'
readonly SW_GREEN='\033[38;5;49m'
readonly SW_RED='\033[38;5;197m'
readonly SW_BG='\033[48;5;53m'
readonly SW_BLACK='\033[38;5;16m'
readonly SW_BOLD='\033[1m'
readonly SW_RESET='\033[0m'

# Current settings (will be loaded from config)
CLIPBOARD_TOOL="${DEFAULT_CLIPBOARD_TOOL}"
NOTIFICATION="${DEFAULT_NOTIFICATION}"
MAX_HISTORY="${DEFAULT_MAX_HISTORY}"
THEME="${DEFAULT_THEME}"
LOG_LEVEL="${DEFAULT_LOG_LEVEL}"
COMPACT_VIEW="${DEFAULT_COMPACT_VIEW}"

# Dependencies
declare -a REQUIRED_DEPS=("gum" "glow" "qdbus" "wl-copy" "jq" "curl" "gtk-launch")

# Function declarations

# Print logo (simplified version)
print_logo() {
    echo -e "${SW_CYAN}QBoss ${SW_PURPLE}KDE Window Manager - v${VERSION}${SW_RESET}"
    echo
}

# Print usage information
print_usage() {
    echo -e "${SW_BOLD}Usage:${SW_RESET} ${APP_NAME} [options] [command] [app-name]"
    echo
    echo -e "${SW_BOLD}Options:${SW_RESET}"
    echo "  -h, --help                Show this help message"
    echo "  -v, --version             Show version information"
    echo "  -i, --install             Install QBoss to system"
    echo "  -u, --update              Update QBoss to the latest version"
    echo "  -r, --remove              Remove QBoss from system"
    echo "  -c, --config              Open configuration settings"
    echo "  -t, --theme <theme>       Use specified theme"
    echo "  -l, --log-level <level>   Set log level (debug, info, warn, error)"
    echo "  --compact                 Use compact view mode"
    echo "  --no-color                Disable colored output"
    echo
    echo -e "${SW_BOLD}Commands:${SW_RESET}"
    echo "  list                      List all windows"
    echo "  search <term>             Search windows by term"
    echo "  class [filter]            List window classes with optional filter"
    echo "  info <window_id>          Show window information"
    echo "  activate <window_id>      Activate specified window"
    echo "  minimize <window_id>      Minimize specified window"
    echo "  maximize <window_id>      Maximize specified window"
    echo "  close <window_id>         Close specified window"
    echo "  monitor                   Monitor window creation/destruction"
    echo "  click                     Capture window properties on click"
    echo "  service [filter]          List DBus services with optional filter"
    echo "  exec <command>            Execute custom qdbus command"
    echo "  script <window_id>        Generate shell script for window interaction"
    echo "  copy <window_id> <type>   Copy window property to clipboard (id|class|title)"
    echo "  apps                      Manage saved applications"
    echo "  app-save <name>           Save current clicked window as an app"
    echo "  app-list                  List saved applications"
    echo "  app-delete <name>         Delete a saved application"
    echo
    echo -e "${SW_BOLD}App Helper:${SW_RESET}"
    echo "  <app-name>                Launch or toggle a saved application"
    echo
    echo -e "${SW_BOLD}Examples:${SW_RESET}"
    echo "  ${APP_NAME}                        # Start interactive TUI"
    echo "  ${APP_NAME} list                   # List all windows"
    echo "  ${APP_NAME} search firefox         # Search for Firefox windows"
    echo "  ${APP_NAME} copy 12345 class       # Copy class of window 12345 to clipboard"
    echo "  ${APP_NAME} app-save firefox       # Save clicked Firefox window as app"
    echo "  ${APP_NAME} firefox                # Launch/toggle Firefox"
    echo
}

# Print version information
print_version() {
    echo -e "${SW_BOLD}${APP_NAME}${SW_RESET} version ${SW_GREEN}${VERSION}${SW_RESET}"
    echo "https://github.com/${GITHUB_REPO}"
}

# Log message with level
log() {
    local level="$1"
    local message="$2"
    local log_file="${LOGS_DIR}/$(date +%Y-%m-%d).log"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Only write log if the level is appropriate
    case "$level" in
        debug)
            [[ "$LOG_LEVEL" == "debug" ]] || return 0
            ;;
        info)
            [[ "$LOG_LEVEL" == "debug" || "$LOG_LEVEL" == "info" ]] || return 0
            ;;
        warn)
            [[ "$LOG_LEVEL" == "debug" || "$LOG_LEVEL" == "info" || "$LOG_LEVEL" == "warn" ]] || return 0
            ;;
        error)
            # Always log errors
            ;;
        *)
            echo -e "${SW_RED}Invalid log level: $level${SW_RESET}" >&2
            return 1
            ;;
    esac
    
    # Ensure log directory exists
    mkdir -p "${LOGS_DIR}"
    
    # Write to log file
    echo "[${timestamp}] [${level^^}] $message" >> "$log_file"
}

# Check if required dependencies are installed
check_dependencies() {
    local missing_deps=()
    
    for dep in "${REQUIRED_DEPS[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo -e "${SW_RED}Error: Missing dependencies: ${missing_deps[*]}${SW_RESET}"
        echo "Please install the missing dependencies and try again."
        echo "For Arch Linux, you can use:"
        echo "  sudo pacman -S charm-gum glow qt5-tools wl-clipboard jq curl gtk3"
        echo "For Debian/Ubuntu, you can use:"
        echo "  sudo apt install charm-gum glow qt5-default wl-clipboard jq curl libgtk-3-bin"
        return 1
    fi
    
    return 0
}

# Create default configuration
create_default_config() {
    # Ensure config directory exists
    mkdir -p "${CONFIG_DIR}"
    mkdir -p "${THEMES_DIR}"
    mkdir -p "${PLUGINS_DIR}"
    mkdir -p "${LOGS_DIR}"
    
    # Create default config file if it doesn't exist
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        cat > "${CONFIG_FILE}" << EOF
{
  "general": {
    "clipboard_tool": "${DEFAULT_CLIPBOARD_TOOL}",
    "notification": ${DEFAULT_NOTIFICATION},
    "max_history": ${DEFAULT_MAX_HISTORY}
  },
  "display": {
    "theme": "${DEFAULT_THEME}",
    "log_level": "${DEFAULT_LOG_LEVEL}",
    "compact_view": ${DEFAULT_COMPACT_VIEW}
  },
  "shortcuts": {
    "exit": "q",
    "back": "escape",
    "help": "h"
  },
  "custom_commands": []
}
EOF
    fi
    
    # Create default apps config file if it doesn't exist
    if [[ ! -f "${APPS_CONFIG_FILE}" ]]; then
        cat > "${APPS_CONFIG_FILE}" << EOF
{
  "apps": []
}
EOF
    fi
    
    # Create default history file if it doesn't exist
    if [[ ! -f "${HISTORY_FILE}" ]]; then
        touch "${HISTORY_FILE}"
    fi
    
    # Create default synthwave theme
    if [[ ! -f "${THEMES_DIR}/synthwave.json" ]]; then
        cat > "${THEMES_DIR}/synthwave.json" << EOF
{
  "name": "Synthwave",
  "author": "QBoss Team",
  "colors": {
    "primary": "206",
    "secondary": "51",
    "accent": "213",
    "background": "53",
    "foreground": "226",
    "success": "49",
    "warning": "208",
    "error": "197",
    "info": "39"
  },
  "styles": {
    "header": "bold",
    "subheader": "bold",
    "text": "normal"
  }
}
EOF
    fi
}

# Load configuration from file
load_config() {
    if [[ -f "${CONFIG_FILE}" ]]; then
        # Load general settings
        CLIPBOARD_TOOL=$(jq -r '.general.clipboard_tool // "'"${DEFAULT_CLIPBOARD_TOOL}"'"' "${CONFIG_FILE}")
        NOTIFICATION=$(jq -r '.general.notification // '"${DEFAULT_NOTIFICATION}"'' "${CONFIG_FILE}")
        MAX_HISTORY=$(jq -r '.general.max_history // '"${DEFAULT_MAX_HISTORY}"'' "${CONFIG_FILE}")
        
        # Load display settings
        THEME=$(jq -r '.display.theme // "'"${DEFAULT_THEME}"'"' "${CONFIG_FILE}")
        LOG_LEVEL=$(jq -r '.display.log_level // "'"${DEFAULT_LOG_LEVEL}"'"' "${CONFIG_FILE}")
        COMPACT_VIEW=$(jq -r '.display.compact_view // '"${DEFAULT_COMPACT_VIEW}"'' "${CONFIG_FILE}")
        
        log "debug" "Configuration loaded from ${CONFIG_FILE}"
        return 0
    else
        log "warn" "Configuration file not found, creating default"
        create_default_config
        load_config
        return 1
    fi
}

# Save configuration to file
save_config() {
    local temp_file
    temp_file=$(mktemp)
    
    cat > "${temp_file}" << EOF
{
  "general": {
    "clipboard_tool": "${CLIPBOARD_TOOL}",
    "notification": ${NOTIFICATION},
    "max_history": ${MAX_HISTORY}
  },
  "display": {
    "theme": "${THEME}",
    "log_level": "${LOG_LEVEL}",
    "compact_view": ${COMPACT_VIEW}
  },
  "shortcuts": $(jq '.shortcuts // {}' "${CONFIG_FILE}"),
  "custom_commands": $(jq '.custom_commands // []' "${CONFIG_FILE}")
}
EOF
    
    mv "${temp_file}" "${CONFIG_FILE}"
    log "info" "Configuration saved to ${CONFIG_FILE}"
}

# Show a notification message
show_notification() {
    local message="$1"
    local title="${2:-QBoss}"
    
    if [[ "${NOTIFICATION}" == "true" ]]; then
        if command -v notify-send &> /dev/null; then
            notify-send "$title" "$message"
        else
            echo -e "${SW_YELLOW}$title${SW_RESET}: $message"
        fi
    fi
}

# Copy text to clipboard
copy_to_clipboard() {
    local text="$1"
    
    if ${CLIPBOARD_TOOL} "$text" 2>/dev/null; then
        show_notification "Copied to clipboard: $text"
        echo "$text" >> "$HISTORY_FILE"
        # Keep history file trimmed to MAX_HISTORY lines
        if [[ "$(wc -l < "$HISTORY_FILE")" -gt "$MAX_HISTORY" ]]; then
            tail -n "$MAX_HISTORY" "$HISTORY_FILE" > "${HISTORY_FILE}.tmp"
            mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
        fi
        log "info" "Copied to clipboard: $text"
        return 0
    else
        show_notification "Failed to copy to clipboard" "Error"
        log "error" "Failed to copy to clipboard: $text"
        return 1
    fi
}

# Display markdown with glow
display_markdown() {
    local markdown="$1"
    local theme_arg=""
    
    # Set theme for glow based on current theme
    case "${THEME}" in
        dark|synthwave)
            theme_arg="dark"
            ;;
        light)
            theme_arg="light"
            ;;
        *)
            theme_arg="dark"
            ;;
    esac
    
    echo "$markdown" | glow -s "$theme_arg" -
}

# Create a temporary markdown file and display it
create_temp_markdown() {
    local content="$1"
    local temp_file
    temp_file=$(mktemp --suffix=.md)
    echo -e "$content" > "$temp_file"
    
    local theme_arg=""
    
    # Set theme for glow based on current theme
    case "${THEME}" in
        dark|synthwave)
            theme_arg="dark"
            ;;
        light)
            theme_arg="light"
            ;;
        *)
            theme_arg="dark"
            ;;
    esac
    
    glow -s "$theme_arg" "$temp_file"
    rm "$temp_file"
}

# Check for KWin DBus Interface Availability
check_kwin_dbus() {
    if ! qdbus org.kde.KWin /KWin 2>/dev/null | grep -q "org.kde.KWin"; then
        echo -e "${SW_RED}Error: KWin DBus interface not available or accessible.${SW_RESET}"
        echo "This script requires access to the KWin DBus interface."
        echo "Make sure you're running KDE and have proper permissions."
        log "error" "KWin DBus interface not available"
        return 1
    fi
    
    # Check if listWindows method exists
    if ! qdbus org.kde.KWin /KWin 2>/dev/null | grep -q "listWindows"; then
        log "warn" "listWindows method not found in KWin DBus interface"
        # We'll handle this in the list_windows function
    fi
    
    return 0
}

# Format window table header
format_window_header() {
    if [[ "${COMPACT_VIEW}" == "true" ]]; then
        echo "| ID | Class | Title |"
        echo "|:---|:------|:------|"
    else
        echo "| ID | Class | Title | Desktop | State |"
        echo "|:---|:------|:------|:--------|:------|"
    fi
}

# Format window table row
format_window_row() {
    local id="$1"
    local class="$2"
    local title="$3"
    
    if [[ "${COMPACT_VIEW}" == "true" ]]; then
        echo "| $id | $class | $title |"
    else
        local desktop
        local is_minimized
        local is_maximized
        local is_fullscreen
        local state=""
        
        desktop=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowDesktop "$id" 2>/dev/null) || desktop="N/A"
        is_minimized=$(qdbus org.kde.KWin /KWin org.kde.KWin.isMinimized "$id" 2>/dev/null) || is_minimized="false"
        is_maximized=$(qdbus org.kde.KWin /KWin org.kde.KWin.isMaximized "$id" 2>/dev/null) || is_maximized="false"
        is_fullscreen=$(qdbus org.kde.KWin /KWin org.kde.KWin.isFullScreen "$id" 2>/dev/null) || is_fullscreen="false"
        
        if [[ "$is_fullscreen" == "true" ]]; then
            state="Fullscreen"
        elif [[ "$is_maximized" == "true" ]]; then
            state="Maximized"
        elif [[ "$is_minimized" == "true" ]]; then
            state="Minimized"
        else
            state="Normal"
        fi
        
        echo "| $id | $class | $title | $desktop | $state |"
    fi
}

# Get window list using alternative method if necessary
get_window_list() {
    local window_ids
    
    # Try the original KWin method first
    window_ids=$(qdbus org.kde.KWin /KWin org.kde.KWin.listWindows 2>/dev/null)
    
    # If that fails, try alternative methods
    if [[ -z "$window_ids" ]]; then
        # Try to use xdotool as a fallback (may not work in Wayland)
        if command -v xdotool &> /dev/null; then
            window_ids=$(xdotool search --all --onlyvisible --name "" 2>/dev/null)
        fi
        
        # If still empty, try to use wmctrl as another fallback
        if [[ -z "$window_ids" ]] && command -v wmctrl &> /dev/null; then
            window_ids=$(wmctrl -l | awk '{print $1}' | cut -d'x' -f2 2>/dev/null)
        fi
    fi
    
    echo "$window_ids"
}

# List all windows
list_windows() {
    local window_ids
    local error_msg
    
    # Try to get window IDs using our fallback function
    window_ids=$(get_window_list) || error_msg="Failed to retrieve window list"
    
    if [[ -n "${error_msg:-}" || -z "$window_ids" ]]; then
        echo -e "${SW_RED}Error listing windows:${SW_RESET} ${error_msg:-No windows found or DBus interface error}"
        log "error" "Error listing windows: ${error_msg:-No windows found or DBus interface error}"
        return 1
    fi
    
    local markdown="# Window List\n\n"
    markdown+=$(format_window_header)
    
    local count=0
    
    for id in $window_ids; do
        local class
        local title
        
        class=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowClass "$id" 2>/dev/null) || class="N/A"
        title=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowTitle "$id" 2>/dev/null) || title="N/A"
        
        # Skip windows with no class or title
        if [[ "$class" == "N/A" && "$title" == "N/A" ]]; then
            continue
        fi
        
        markdown+=$(format_window_row "$id" "$class" "$title")
        ((count++))
    done
    
    markdown+="\n\n${count} windows found."
    
    create_temp_markdown "$markdown"
    log "info" "Listed $count windows"
    
    # In interactive mode, allow selection with gum
    if [[ -z "${CLI_MODE:-}" ]]; then
        local selected_id
        selected_id=$(echo "$window_ids" | gum filter --prompt "Select a window ID: ")
        
        if [[ -n "$selected_id" ]]; then
            window_detail_menu "$selected_id"
        fi
    fi
    
    return 0
}

# Get detailed information about a window
get_window_info() {
    local window_id="$1"
    local error_msg
    
    # Check if window_id exists
    local window_ids
    window_ids=$(get_window_list)
    
    if ! echo "$window_ids" | grep -q "$window_id"; then
        echo -e "${SW_RED}Error: Window ID $window_id does not exist.${SW_RESET}"
        log "error" "Window ID $window_id does not exist"
        return 1
    fi
    
    local class
    local title
    local desktop
    local geometry
    local is_fullscreen
    local is_minimized
    local is_maximized
    local pid
    local resource_name
    local resource_class
    
    class=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowClass "$window_id" 2>/dev/null) || class="N/A"
    title=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowTitle "$window_id" 2>/dev/null) || title="N/A"
    desktop=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowDesktop "$window_id" 2>/dev/null) || desktop="N/A"
    geometry=$(qdbus org.kde.KWin /KWin org.kde.KWin.getWindowGeometry "$window_id" 2>/dev/null) || geometry="N/A"
    is_fullscreen=$(qdbus org.kde.KWin /KWin org.kde.KWin.isFullScreen "$window_id" 2>/dev/null) || is_fullscreen="N/A"
    is_minimized=$(qdbus org.kde.KWin /KWin org.kde.KWin.isMinimized "$window_id" 2>/dev/null) || is_minimized="N/A"
    is_maximized=$(qdbus org.kde.KWin /KWin org.kde.KWin.isMaximized "$window_id" 2>/dev/null) || is_maximized="N/A"
    
    # Try to get PID using xprop (fallback)
    pid=$(xprop -id "$window_id" _NET_WM_PID 2>/dev/null | cut -d' ' -f3) || pid="N/A"
    
    # Try to get resource name and class
    resource_info=$(xprop -id "$window_id" WM_CLASS 2>/dev/null) || resource_info=""
    if [[ -n "$resource_info" ]]; then
        resource_name=$(echo "$resource_info" | sed -n 's/.*"\(.*\)", "\(.*\)".*/\1/p')
        resource_class=$(echo "$resource_info" | sed -n 's/.*"\(.*\)", "\(.*\)".*/\2/p')
    else
        resource_name="N/A"
        resource_class="N/A"
    fi
    
    local markdown="# Window Details\n\n"
    markdown+="## Window ID: $window_id\n\n"
    markdown+="- **Title**: $title\n"
    markdown+="- **Class**: $class\n"
    markdown+="- **Resource Name**: $resource_name\n"
    markdown+="- **Resource Class**: $resource_class\n"
    markdown+="- **Desktop**: $desktop\n"
    markdown+="- **Geometry**: $geometry\n"
    markdown+="- **Process ID**: $pid\n"
    markdown+="- **Fullscreen**: $is_fullscreen\n"
    markdown+="- **Minimized**: $is_minimized\n"
    markdown+="- **Maximized**: $is_maximized\n\n"
    
    if [[ -z "${CLI_MODE:-}" ]]; then
        markdown+="## Available Actions\n\n"
        markdown+="- Copy window ID to clipboard\n"
        markdown+="- Copy window class to clipboard\n"
        markdown+="- Copy window title to clipboard\n"
        markdown+="- Activate window\n"
        markdown+="- Minimize window\n"
        markdown+="- Maximize window\n"
        markdown+="- Close window\n"
    fi
    
    create_temp_markdown "$markdown"
    log "info" "Displayed info for window ID $window_id"
    
    return 0
}

# Window detail menu
window_detail_menu() {
    local window_id="$1"
    
    get_window_info "$window_id"
    
    local class
    class=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowClass "$window_id" 2>/dev/null) || class="N/A"
    
    local title
    title=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowTitle "$window_id" 2>/dev/null) || title="N/A"
    
    local action
    action=$(gum choose \
        "Copy window ID to clipboard" \
        "Copy window class to clipboard" \
        "Copy window title to clipboard" \
        "Activate window" \
        "Minimize window" \
        "Maximize window" \
        "Toggle fullscreen" \
        "Close window" \
        "Generate script for this window" \
        "Save as application" \
        "Back to main menu")
    
    case "$action" in
        "Copy window ID to clipboard")
            copy_to_clipboard "$window_id"
            window_detail_menu "$window_id"
            ;;
        "Copy window class to clipboard")
            copy_to_clipboard "$class"
            window_detail_menu "$window_id"
            ;;
        "Copy window title to clipboard")
            copy_to_clipboard "$title"
            window_detail_menu "$window_id"
            ;;
        "Activate window")
            qdbus org.kde.KWin /KWin org.kde.KWin.setCurrentWindow "$window_id"
            show_notification "Window activated: $title"
            window_detail_menu "$window_id"
            ;;
        "Minimize window")
            qdbus org.kde.KWin /KWin org.kde.KWin.minimizeWindow "$window_id"
            show_notification "Window minimized: $title"
            window_detail_menu "$window_id"
            ;;
        "Maximize window")
            qdbus org.kde.KWin /KWin org.kde.KWin.maximizeWindow "$window_id"
            show_notification "Window maximized: $title"
            window_detail_menu "$window_id"
            ;;
        "Toggle fullscreen")
            # Check current fullscreen state
            local is_fullscreen
            is_fullscreen=$(qdbus org.kde.KWin /KWin org.kde.KWin.isFullScreen "$window_id" 2>/dev/null)
            
            if [[ "$is_fullscreen" == "true" ]]; then
                qdbus org.kde.KWin /KWin org.kde.KWin.setFullScreen "$window_id" false
                show_notification "Fullscreen disabled: $title"
            else
                qdbus org.kde.KWin /KWin org.kde.KWin.setFullScreen "$window_id" true
                show_notification "Fullscreen enabled: $title"
            fi
            window_detail_menu "$window_id"
            ;;
        "Close window")
            qdbus org.kde.KWin /KWin org.kde.KWin.closeWindow "$window_id"
            show_notification "Window closed: $title"
            main_menu
            ;;
        "Generate script for this window")
            generate_qdbus_script "$window_id"
            window_detail_menu "$window_id"
            ;;
        "Save as application")
            local app_name
            app_name=$(gum input --prompt "Enter a name for this application: ")
            
            if [[ -n "$app_name" ]]; then
                save_app_config "$app_name" "$window_id"
                window_detail_menu "$window_id"
            else
                echo -e "${SW_YELLOW}App name cannot be empty.${SW_RESET}"
                window_detail_menu "$window_id"
            fi
            ;;
        "Back to main menu")
            main_menu
            ;;
    esac
}

# Search for windows by class or title
search_windows() {
    local search_type
    local search_term="$1"
    
    if [[ -z "$search_term" ]]; then
        if [[ -z "${CLI_MODE:-}" ]]; then
            search_type=$(gum choose "Search by class" "Search by title" "Search by both")
            search_term=$(gum input --prompt "Enter search term: ")
        else
            echo -e "${SW_YELLOW}Search term cannot be empty.${SW_RESET}"
            log "warn" "Search term cannot be empty"
            return 1
        fi
    else
        if [[ -z "${CLI_MODE:-}" ]]; then
            search_type=$(gum choose "Search by class" "Search by title" "Search by both")
        else
            search_type="Search by both"
        fi
    fi
    
    if [[ -z "$search_term" ]]; then
        echo -e "${SW_YELLOW}Search term cannot be empty.${SW_RESET}"
        log "warn" "Search term cannot be empty"
        return 1
    fi
    
    local window_ids
    window_ids=$(get_window_list)
    
    if [[ -z "$window_ids" ]]; then
        echo -e "${SW_YELLOW}No windows found.${SW_RESET}"
        log "info" "No windows found"
        return 0
    fi
    
    local markdown="# Search Results for \"$search_term\"\n\n"
    markdown+=$(format_window_header)
    
    local matches=()
    local match_ids=()
    
    for id in $window_ids; do
        local class
        local title
        local match=""
        
        class=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowClass "$id" 2>/dev/null) || class="N/A"
        title=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowTitle "$id" 2>/dev/null) || title="N/A"
        
        if [[ "$search_type" == "Search by class" && "$class" == *"$search_term"* ]]; then
            match="Class"
            matches+=("$id:$class:$title")
            match_ids+=("$id")
            markdown+=$(format_window_row "$id" "$class" "$title")
        elif [[ "$search_type" == "Search by title" && "$title" == *"$search_term"* ]]; then
            match="Title"
            matches+=("$id:$class:$title")
            match_ids+=("$id")
            markdown+=$(format_window_row "$id" "$class" "$title")
        elif [[ "$search_type" == "Search by both" && ("$class" == *"$search_term"* || "$title" == *"$search_term"*) ]]; then
            if [[ "$class" == *"$search_term"* ]]; then
                match="Class"
            else
                match="Title"
            fi
            matches+=("$id:$class:$title")
            match_ids+=("$id")
            markdown+=$(format_window_row "$id" "$class" "$title")
        fi
    done
    
    if [[ ${#matches[@]} -eq 0 ]]; then
        echo -e "${SW_YELLOW}No matches found for '$search_term'.${SW_RESET}"
        log "info" "No matches found for '$search_term'"
        return 0
    fi
    
    markdown+="\n\n${#matches[@]} matches found."
    
    create_temp_markdown "$markdown"
    log "info" "Search for '$search_term' found ${#matches[@]} matches"
    
    # In interactive mode, allow selection with gum
    if [[ -z "${CLI_MODE:-}" ]]; then
        local display_matches=()
        
        for match in "${matches[@]}"; do
            local id="${match%%:*}"
            local rest="${match#*:}"
            local class="${rest%%:*}"
            local title="${rest#*:}"
            
            display_matches+=("ID: $id | Class: $class | Title: $title")
        done
        
        local selected_match
        selected_match=$(printf "%s\n" "${display_matches[@]}" | gum filter --prompt "Select a window: ")
        
        if [[ -n "$selected_match" ]]; then
            local selected_id
            selected_id=$(echo "$selected_match" | sed -n 's/ID: \([0-9]*\) .*/\1/p')
            
            if [[ -n "$selected_id" ]]; then
                window_detail_menu "$selected_id"
            fi
        fi
    fi
    
    return 0
}

# List window classes
list_window_classes() {
    local filter="$1"
    local window_ids
    window_ids=$(get_window_list)
    
    if [[ -z "$window_ids" ]]; then
        echo -e "${SW_YELLOW}No windows found.${SW_RESET}"
        log "info" "No windows found"
        return 0
    fi
    
    local classes=()
    local class_to_id=()
    
    for id in $window_ids; do
        local class
        class=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowClass "$id" 2>/dev/null) || class="N/A"
        
        if [[ -n "$filter" && "$class" != *"$filter"* ]]; then
            continue
        fi
        
        if [[ ! " ${classes[*]} " =~ " ${class} " ]]; then
            classes+=("$class")
        fi
        
        class_to_id+=("$class:$id")
    done
    
    if [[ ${#classes[@]} -eq 0 ]]; then
        if [[ -n "$filter" ]]; then
            echo -e "${SW_YELLOW}No classes found matching '$filter'.${SW_RESET}"
            log "info" "No classes found matching '$filter'"
        else
            echo -e "${SW_YELLOW}No classes found.${SW_RESET}"
            log "info" "No classes found"
        fi
        return 0
    fi
    
    local markdown="# Window Classes\n\n"
    markdown+="| Class | Window Count | Example Window |\n"
    markdown+="|:------|:------------|:---------------|\n"
    
    for class in "${classes[@]}"; do
        local count=0
        local example_id=""
        local example_title=""
        
        for mapping in "${class_to_id[@]}"; do
            local c="${mapping%%:*}"
            local id="${mapping#*:}"
            
            if [[ "$c" == "$class" ]]; then
                ((count++))
                
                if [[ -z "$example_id" ]]; then
                    example_id="$id"
                    example_title=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowTitle "$id" 2>/dev/null) || example_title="N/A"
                    
                    # Truncate long titles
                    if [[ "${#example_title}" -gt 40 ]]; then
                        example_title="${example_title:0:37}..."
                    fi
                fi
            fi
        done
        
        markdown+="| $class | $count | $example_title |\n"
    done
    
    markdown+="\n\n${#classes[@]} classes found."
    
    create_temp_markdown "$markdown"
    log "info" "Listed ${#classes[@]} window classes"
    
    # In interactive mode, allow selection with gum
    if [[ -z "${CLI_MODE:-}" ]]; then
        local selected_class
        selected_class=$(printf "%s\n" "${classes[@]}" | gum filter --prompt "Select a window class: ")
        
        if [[ -n "$selected_class" ]]; then
            # Get window IDs for the selected class
            local class_window_ids=()
            
            for mapping in "${class_to_id[@]}"; do
                local c="${mapping%%:*}"
                local id="${mapping#*:}"
                
                if [[ "$c" == "$selected_class" ]]; then
                    class_window_ids+=("$id")
                fi
            done
            
            local markdown="# Windows of Class: $selected_class\n\n"
            markdown+=$(format_window_header)
            
            for id in "${class_window_ids[@]}"; do
                local title
                title=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowTitle "$id" 2>/dev/null) || title="N/A"
                
                markdown+=$(format_window_row "$id" "$selected_class" "$title")
            done
            
            create_temp_markdown "$markdown"
            
            # Ask if user wants to copy the class to clipboard
            if gum confirm "Copy class '$selected_class' to clipboard?"; then
                copy_to_clipboard "$selected_class"
            fi
            
            # Allow selection of a window from this class
            local selected_id
            selected_id=$(printf "%s\n" "${class_window_ids[@]}" | gum filter --prompt "Select a window ID: ")
            
            if [[ -n "$selected_id" ]]; then
                window_detail_menu "$selected_id"
            fi
        fi
    fi
    
    return 0
}

# Get clipboard history
get_clipboard_history() {
    if [[ ! -f "$HISTORY_FILE" || ! -s "$HISTORY_FILE" ]]; then
        echo -e "${SW_YELLOW}No clipboard history found.${SW_RESET}"
        log "info" "No clipboard history found"
        return 0
    fi
    
    local history
    history=$(tac "$HISTORY_FILE")
    
    local markdown="# Clipboard History\n\n"
    markdown+="| Item |\n"
    markdown+="|:----|\n"
    
    while IFS= read -r item; do
        markdown+="| $item |\n"
    done <<< "$history"
    
    create_temp_markdown "$markdown"
    log "info" "Displayed clipboard history"
    
    # Allow selection with gum
    local selected_item
    selected_item=$(echo "$history" | gum filter --prompt "Select an item to copy to clipboard: ")
    
    if [[ -n "$selected_item" ]]; then
        copy_to_clipboard "$selected_item"
    fi
    
    return 0
}

# List available qdbus services
list_qdbus_services() {
    local filter="$1"
    local services
    services=$(qdbus)
    
    if [[ -z "$services" ]]; then
        echo -e "${SW_YELLOW}No DBus services found.${SW_RESET}"
        log "info" "No DBus services found"
        return 0
    fi
    
    if [[ -z "$filter" && -z "${CLI_MODE:-}" ]]; then
        filter=$(gum input --prompt "Filter services (leave empty for all): ")
    fi
    
    local filtered_services=()
    
    if [[ -n "$filter" ]]; then
        while IFS= read -r service; do
            if [[ "$service" == *"$filter"* ]]; then
                filtered_services+=("$service")
            fi
        done <<< "$services"
    else
        mapfile -t filtered_services <<< "$services"
    fi
    
    if [[ ${#filtered_services[@]} -eq 0 ]]; then
        if [[ -n "$filter" ]]; then
            echo -e "${SW_YELLOW}No services found matching '$filter'.${SW_RESET}"
            log "info" "No services found matching '$filter'"
        else
            echo -e "${SW_YELLOW}No services found.${SW_RESET}"
            log "info" "No services found"
        fi
        return 0
    fi
    
    local markdown="# DBus Services\n\n"
    
    if [[ -n "$filter" ]]; then
        markdown+="Filtered by: \"$filter\"\n\n"
    fi
    
    markdown+="| Service |\n"
    markdown+="|:-------|\n"
    
    for service in "${filtered_services[@]}"; do
        markdown+="| $service |\n"
    done
    
    markdown+="\n\n${#filtered_services[@]} services found."
    
    create_temp_markdown "$markdown"
    log "info" "Listed ${#filtered_services[@]} DBus services"
    
    # In interactive mode, allow selection with gum
    if [[ -z "${CLI_MODE:-}" ]]; then
        local selected_service
        selected_service=$(printf "%s\n" "${filtered_services[@]}" | gum filter --prompt "Select a service: ")
        
        if [[ -n "$selected_service" ]]; then
            # Get interfaces for the selected service
            list_qdbus_interfaces "$selected_service"
        fi
    fi
    
    return 0
}

# List DBus interfaces for a service
list_qdbus_interfaces() {
    local service="$1"
    local interfaces
    
    interfaces=$(qdbus "$service")
    
    if [[ -z "$interfaces" ]]; then
        echo -e "${SW_YELLOW}No interfaces found for service '$service'.${SW_RESET}"
        log "info" "No interfaces found for service '$service'"
        return 0
    fi
    
    local markdown="# Interfaces for $service\n\n"
    markdown+="| Interface |\n"
    markdown+="|:----------|\n"
    
    while IFS= read -r interface; do
        markdown+="| $interface |\n"
    done <<< "$interfaces"
    
    create_temp_markdown "$markdown"
    log "info" "Listed interfaces for service '$service'"
    
    # In interactive mode, allow selection with gum
    if [[ -z "${CLI_MODE:-}" ]]; then
        local selected_interface
        selected_interface=$(echo "$interfaces" | gum filter --prompt "Select an interface: ")
        
        if [[ -n "$selected_interface" ]]; then
            # Get methods for the selected interface
            list_qdbus_methods "$service" "$selected_interface"
        fi
    fi
    
    return 0
}

# List DBus methods for a service and interface
list_qdbus_methods() {
    local service="$1"
    local interface="$2"
    local methods
    
    methods=$(qdbus "$service" "$interface")
    
    if [[ -z "$methods" ]]; then
        echo -e "${SW_YELLOW}No methods found for interface '$interface'.${SW_RESET}"
        log "info" "No methods found for interface '$interface'"
        return 0
    fi
    
    local markdown="# Methods for $service $interface\n\n"
    markdown+="| Method |\n"
    markdown+="|:-------|\n"
    
    while IFS= read -r method; do
        markdown+="| $method |\n"
    done <<< "$methods"
    
    create_temp_markdown "$markdown"
    log "info" "Listed methods for interface '$interface'"
    
    # In interactive mode, ask if user wants to copy any method
    if [[ -z "${CLI_MODE:-}" ]]; then
        local selected_method
        selected_method=$(echo "$methods" | gum filter --prompt "Select a method to copy or execute: ")
        
        if [[ -n "$selected_method" ]]; then
            local full_method="qdbus $service $interface $selected_method"
            
            # Ask if user wants to execute the method
            if gum confirm "Execute '$full_method'?"; then
                local result
                result=$(eval "$full_method" 2>&1)
                local exit_code=$?
                
                if [[ $exit_code -eq 0 ]]; then
                    echo -e "${SW_GREEN}Result:${SW_RESET}"
                    echo "$result"
                    log "info" "Executed method '$full_method'"
                    
                    # Ask if user wants to copy the result to clipboard
                    if [[ -n "$result" ]] && gum confirm "Copy result to clipboard?"; then
                        copy_to_clipboard "$result"
                    fi
                else
                    echo -e "${SW_RED}Error:${SW_RESET} $result"
                    log "error" "Error executing method '$full_method': $result"
                fi
            else
                # Copy the method command to clipboard
                copy_to_clipboard "$full_method"
            fi
        fi
    fi
    
    return 0
}

# Monitor window creation/destruction
monitor_windows() {
    echo -e "${SW_BLUE}Monitoring window creation/destruction...${SW_RESET}"
    echo -e "${SW_YELLOW}Press Ctrl+C to stop monitoring.${SW_RESET}"
    log "info" "Started window monitoring"
    
    local initial_windows
    initial_windows=$(get_window_list)
    
    # Convert to array
    local -a window_array
    mapfile -t window_array <<< "$initial_windows"
    
    echo -e "${SW_GREEN}Initial windows:${SW_RESET}"
    for id in "${window_array[@]}"; do
        local class
        local title
        
        class=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowClass "$id" 2>/dev/null) || class="N/A"
        title=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowTitle "$id" 2>/dev/null) || title="N/A"
        
        echo "ID: $id, Class: $class, Title: $title"
    done
    
    echo
    
    # Monitor in a loop
    while true; do
        sleep 1
        
        local current_windows
        current_windows=$(get_window_list)
        
        # Convert to array
        local -a current_array
        mapfile -t current_array <<< "$current_windows"
        
        # Check for new windows
        for id in "${current_array[@]}"; do
            if ! printf "%s\n" "${window_array[@]}" | grep -q "^$id$"; then
                local class
                local title
                
                class=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowClass "$id" 2>/dev/null) || class="N/A"
                title=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowTitle "$id" 2>/dev/null) || title="N/A"
                
                echo -e "${SW_GREEN}New window:${SW_RESET} ID: $id, Class: $class, Title: $title"
                log "info" "New window: ID: $id, Class: $class, Title: $title"
            fi
        done
        
        # Check for closed windows
        for id in "${window_array[@]}"; do
            if ! printf "%s\n" "${current_array[@]}" | grep -q "^$id$"; then
                echo -e "${SW_RED}Closed window:${SW_RESET} ID: $id"
                log "info" "Closed window: ID: $id"
            fi
        done
        
        # Update window array
        window_array=("${current_array[@]}")
    done
}

# Capture window properties on click
capture_window_on_click() {
    echo -e "${SW_BLUE}Click on a window to capture its properties...${SW_RESET}"
    log "info" "Started window capture on click"
    
    local pid
    pid=$(xdotool selectwindow getwindowpid 2>/dev/null)
    
    if [[ -z "$pid" ]]; then
        echo -e "${SW_RED}Failed to capture window. Make sure xdotool is installed.${SW_RESET}"
        log "error" "Failed to capture window with xdotool"
        return 1
    fi
    
    # Try to find the window ID from PID
    local window_ids
    window_ids=$(get_window_list)
    
    for id in $window_ids; do
        local window_pid
        window_pid=$(xprop -id "$id" _NET_WM_PID 2>/dev/null | cut -d' ' -f3)
        
        if [[ "$window_pid" == "$pid" ]]; then
            log "info" "Captured window ID $id on click"
            
            if [[ -z "${CLI_MODE:-}" ]]; then
                window_detail_menu "$id"
            else
                get_window_info "$id"
            fi
            
            return 0
        fi
    done
    
    echo -e "${SW_YELLOW}Could not find KWin window ID for process ID $pid.${SW_RESET}"
    log "warn" "Could not find KWin window ID for process ID $pid"
    return 1
}

# Execute custom qdbus command
execute_custom_qdbus() {
    local command="$1"
    
    if [[ -z "$command" ]]; then
        if [[ -z "${CLI_MODE:-}" ]]; then
            command=$(gum input --prompt "Enter qdbus command (without 'qdbus'): ")
        else
            echo -e "${SW_YELLOW}Command cannot be empty.${SW_RESET}"
            log "warn" "Custom qdbus command cannot be empty"
            return 1
        fi
    fi
    
    if [[ -z "$command" ]]; then
        echo -e "${SW_YELLOW}Command cannot be empty.${SW_RESET}"
        log "warn" "Custom qdbus command cannot be empty"
        return 1
    fi
    
    local full_command="qdbus $command"
    local result
    
    result=$(eval "$full_command" 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        echo -e "${SW_RED}Error executing command:${SW_RESET} $result"
        log "error" "Error executing command '$full_command': $result"
        return 1
    fi
    
    echo -e "${SW_GREEN}Result:${SW_RESET}"
    echo "$result"
    log "info" "Executed custom command '$full_command'"
    
    # In interactive mode, ask if user wants to copy
    if [[ -z "${CLI_MODE:-}" ]]; then
        # Ask if user wants to copy the result to clipboard
        if [[ -n "$result" ]] && gum confirm "Copy result to clipboard?"; then
            copy_to_clipboard "$result"
        fi
        
        # Ask if user wants to copy the command to clipboard
        if gum confirm "Copy command to clipboard?"; then
            copy_to_clipboard "$full_command"
        fi
    fi
    
    return 0
}

# Generate qdbus shell script
generate_qdbus_script() {
    local window_id="$1"
    
    if [[ -z "$window_id" ]]; then
        if [[ -z "${CLI_MODE:-}" ]]; then
            window_id=$(gum input --prompt "Enter window ID (leave empty to select from list): ")
            
            if [[ -z "$window_id" ]]; then
                local window_ids
                window_ids=$(get_window_list)
                
                local markdown="# Select Window\n\n"
                markdown+=$(format_window_header)
                
                for id in $window_ids; do
                    local class
                    local title
                    
                    class=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowClass "$id" 2>/dev/null) || class="N/A"
                    title=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowTitle "$id" 2>/dev/null) || title="N/A"
                    
                    markdown+=$(format_window_row "$id" "$class" "$title")
                done
                
                create_temp_markdown "$markdown"
                
                window_id=$(echo "$window_ids" | gum filter --prompt "Select a window ID: ")
            fi
        else
            echo -e "${SW_YELLOW}Window ID cannot be empty.${SW_RESET}"
            log "warn" "Window ID cannot be empty for script generation"
            return 1
        fi
    fi
    
    if [[ -z "$window_id" ]]; then
        echo -e "${SW_YELLOW}No window ID selected.${SW_RESET}"
        log "warn" "No window ID selected for script generation"
        return 1
    fi
    
    local class
    class=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowClass "$window_id" 2>/dev/null) || class="N/A"
    
    local title
    title=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowTitle "$window_id" 2>/dev/null) || title="N/A"
    
    # Sanitize class for filename
    local sanitized_class
    sanitized_class=$(echo "$class" | tr -c '[:alnum:]' '_')
    
    local script="#!/bin/bash\n\n"
    script+="# QBoss-generated script to interact with window: $title ($class)\n"
    script+="# Generated on $(date +"%Y-%m-%d %H:%M:%S")\n\n"
    script+="# Get window ID by class\n"
    script+="get_window_id_by_class() {\n"
    script+="    local class=\"$class\"\n"
    script+="    local window_ids\n\n"
    script+="    window_ids=\$(qdbus org.kde.KWin /KWin org.kde.KWin.listWindows 2>/dev/null)\n\n"
    script+="    # If listWindows fails, try alternative methods\n"
    script+="    if [[ -z \"\$window_ids\" ]]; then\n"
    script+="        if command -v xdotool &> /dev/null; then\n"
    script+="            window_ids=\$(xdotool search --all --onlyvisible --name \"\" 2>/dev/null)\n"
    script+="        elif command -v wmctrl &> /dev/null; then\n"
    script+="            window_ids=\$(wmctrl -l | awk '{print \$1}' | cut -d'x' -f2 2>/dev/null)\n"
    script+="        fi\n"
    script+="    fi\n\n"
    script+="    for id in \$window_ids; do\n"
    script+="        local window_class\n"
    script+="        window_class=\$(qdbus org.kde.KWin /KWin org.kde.KWin.windowClass \"\$id\" 2>/dev/null)\n\n"
    script+="        if [[ \"\$window_class\" == \"\$class\" ]]; then\n"
    script+="            echo \"\$id\"\n"
    script+="            return 0\n"
    script+="        fi\n"
    script+="    done\n\n"
    script+="    return 1\n"
    script+="}\n\n"
    script+="# Example usage\n"
    script+="window_id=\$(get_window_id_by_class)\n\n"
    script+="if [[ -n \"\$window_id\" ]]; then\n"
    script+="    echo \"Found window ID: \$window_id\"\n"
    script+="    \n"
    script+="    # Available actions (uncomment to use)\n"
    script+="    # qdbus org.kde.KWin /KWin org.kde.KWin.setCurrentWindow \"\$window_id\"   # Activate window\n"
    script+="    # qdbus org.kde.KWin /KWin org.kde.KWin.minimizeWindow \"\$window_id\"     # Minimize window\n"
    script+="    # qdbus org.kde.KWin /KWin org.kde.KWin.maximizeWindow \"\$window_id\"     # Maximize window\n"
    script+="    # qdbus org.kde.KWin /KWin org.kde.KWin.setFullScreen \"\$window_id\" true # Set fullscreen\n"
    script+="    # qdbus org.kde.KWin /KWin org.kde.KWin.closeWindow \"\$window_id\"        # Close window\n\n"
    script+="    # Get window properties\n"
    script+="    # title=\$(qdbus org.kde.KWin /KWin org.kde.KWin.windowTitle \"\$window_id\")\n"
    script+="    # desktop=\$(qdbus org.kde.KWin /KWin org.kde.KWin.windowDesktop \"\$window_id\")\n"
    script+="    # geometry=\$(qdbus org.kde.KWin /KWin org.kde.KWin.getWindowGeometry \"\$window_id\")\n"
    script+="else\n"
    script+="    echo \"No window found with class: $class\"\n"
    script+="fi\n"
    
    local script_file="$HOME/${APP_NAME}_${sanitized_class}_script.sh"
    echo -e "$script" > "$script_file"
    chmod +x "$script_file"
    
    echo -e "${SW_GREEN}Script created:${SW_RESET} $script_file"
    log "info" "Generated script for window ID $window_id: $script_file"
    
    # In interactive mode, ask if user wants to view the script
    if [[ -z "${CLI_MODE:-}" ]]; then
        if gum confirm "View the script?"; then
            glow -s dark "$script_file"
        fi
    fi
    
    return 0
}

# Copy window property to clipboard
copy_window_property() {
    local window_id="$1"
    local property="$2"
    
    if [[ -z "$window_id" || -z "$property" ]]; then
        echo -e "${SW_YELLOW}Window ID and property type required.${SW_RESET}"
        log "warn" "Window ID and property type required for copy operation"
        return 1
    fi
    
    # Check if window_id exists
    local window_ids
    window_ids=$(get_window_list)
    if ! echo "$window_ids" | grep -q "$window_id"; then
        echo -e "${SW_RED}Error: Window ID $window_id does not exist.${SW_RESET}"
        log "error" "Window ID $window_id does not exist"
        return 1
    fi
    
    case "$property" in
        id)
            copy_to_clipboard "$window_id"
            echo -e "${SW_GREEN}Window ID copied to clipboard:${SW_RESET} $window_id"
            ;;
        class)
            local class
            class=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowClass "$window_id" 2>/dev/null) || class="N/A"
            
            if [[ "$class" == "N/A" ]]; then
                echo -e "${SW_RED}Error: Could not get window class.${SW_RESET}"
                log "error" "Could not get class for window ID $window_id"
                return 1
            fi
            
            copy_to_clipboard "$class"
            echo -e "${SW_GREEN}Window class copied to clipboard:${SW_RESET} $class"
            ;;
        title)
            local title
            title=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowTitle "$window_id" 2>/dev/null) || title="N/A"
            
            if [[ "$title" == "N/A" ]]; then
                echo -e "${SW_RED}Error: Could not get window title.${SW_RESET}"
                log "error" "Could not get title for window ID $window_id"
                return 1
            fi
            
            copy_to_clipboard "$title"
            echo -e "${SW_GREEN}Window title copied to clipboard:${SW_RESET} $title"
            ;;
        *)
            echo -e "${SW_RED}Error: Invalid property type. Use 'id', 'class', or 'title'.${SW_RESET}"
            log "error" "Invalid property type: $property"
            return 1
            ;;
    esac
    
    return 0
}

# Activate/focus a window
activate_window() {
    local window_id="$1"
    
    if [[ -z "$window_id" ]]; then
        echo -e "${SW_YELLOW}Window ID required.${SW_RESET}"
        log "warn" "Window ID required for activation"
        return 1
    fi
    
    # Check if window_id exists
    local window_ids
    window_ids=$(get_window_list)
    if ! echo "$window_ids" | grep -q "$window_id"; then
        echo -e "${SW_RED}Error: Window ID $window_id does not exist.${SW_RESET}"
        log "error" "Window ID $window_id does not exist"
        return 1
    fi
    
    local title
    title=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowTitle "$window_id" 2>/dev/null) || title="N/A"
    
    if qdbus org.kde.KWin /KWin org.kde.KWin.setCurrentWindow "$window_id"; then
        echo -e "${SW_GREEN}Window activated:${SW_RESET} $title"
        show_notification "Window activated: $title"
        log "info" "Activated window ID $window_id: $title"
        return 0
    else
        echo -e "${SW_RED}Error: Failed to activate window.${SW_RESET}"
        log "error" "Failed to activate window ID $window_id"
        return 1
    fi
}

# Minimize a window
minimize_window() {
    local window_id="$1"
    
    if [[ -z "$window_id" ]]; then
        echo -e "${SW_YELLOW}Window ID required.${SW_RESET}"
        log "warn" "Window ID required for minimize operation"
        return 1
    fi
    
    # Check if window_id exists
    local window_ids
    window_ids=$(get_window_list)
    if ! echo "$window_ids" | grep -q "$window_id"; then
        echo -e "${SW_RED}Error: Window ID $window_id does not exist.${SW_RESET}"
        log "error" "Window ID $window_id does not exist"
        return 1
    fi
    
    local title
    title=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowTitle "$window_id" 2>/dev/null) || title="N/A"
    
    if qdbus org.kde.KWin /KWin org.kde.KWin.minimizeWindow "$window_id"; then
        echo -e "${SW_GREEN}Window minimized:${SW_RESET} $title"
        show_notification "Window minimized: $title"
        log "info" "Minimized window ID $window_id: $title"
        return 0
    else
        echo -e "${SW_RED}Error: Failed to minimize window.${SW_RESET}"
        log "error" "Failed to minimize window ID $window_id"
        return 1
    fi
}

# Maximize a window
maximize_window() {
    local window_id="$1"
    
    if [[ -z "$window_id" ]]; then
        echo -e "${SW_YELLOW}Window ID required.${SW_RESET}"
        log "warn" "Window ID required for maximize operation"
        return 1
    fi
    
    # Check if window_id exists
    local window_ids
    window_ids=$(get_window_list)
    if ! echo "$window_ids" | grep -q "$window_id"; then
        echo -e "${SW_RED}Error: Window ID $window_id does not exist.${SW_RESET}"
        log "error" "Window ID $window_id does not exist"
        return 1
    fi
    
    local title
    title=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowTitle "$window_id" 2>/dev/null) || title="N/A"
    
    if qdbus org.kde.KWin /KWin org.kde.KWin.maximizeWindow "$window_id"; then
        echo -e "${SW_GREEN}Window maximized:${SW_RESET} $title"
        show_notification "Window maximized: $title"
        log "info" "Maximized window ID $window_id: $title"
        return 0
    else
        echo -e "${SW_RED}Error: Failed to maximize window.${SW_RESET}"
        log "error" "Failed to maximize window ID $window_id"
        return 1
    fi
}

# Close a window
close_window() {
    local window_id="$1"
    
    if [[ -z "$window_id" ]]; then
        echo -e "${SW_YELLOW}Window ID required.${SW_RESET}"
        log "warn" "Window ID required for close operation"
        return 1
    fi
    
    # Check if window_id exists
    local window_ids
    window_ids=$(get_window_list)
    if ! echo "$window_ids" | grep -q "$window_id"; then
        echo -e "${SW_RED}Error: Window ID $window_id does not exist.${SW_RESET}"
        log "error" "Window ID $window_id does not exist"
        return 1
    fi
    
    local title
    title=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowTitle "$window_id" 2>/dev/null) || title="N/A"
    
    if qdbus org.kde.KWin /KWin org.kde.KWin.closeWindow "$window_id"; then
        echo -e "${SW_GREEN}Window closed:${SW_RESET} $title"
        show_notification "Window closed: $title"
        log "info" "Closed window ID $window_id: $title"
        return 0
    else
        echo -e "${SW_RED}Error: Failed to close window.${SW_RESET}"
        log "error" "Failed to close window ID $window_id"
        return 1
    fi
}

# Open configuration settings
open_config_settings() {
    local setting
    setting=$(gum choose \
        "General Settings" \
        "Display Settings" \
        "Notification Settings" \
        "App Helper Settings" \
        "Advanced Settings" \
        "Back to main menu")
    
    case "$setting" in
        "General Settings")
            local general_setting
            general_setting=$(gum choose \
                "Clipboard Tool" \
                "Max History Size" \
                "Back")
            
            case "$general_setting" in
                "Clipboard Tool")
                    local clipboard_option
                    clipboard_option=$(gum choose "wl-copy" "xclip" "pbcopy" "Back")
                    
                    if [[ "$clipboard_option" != "Back" ]]; then
                        CLIPBOARD_TOOL="$clipboard_option"
                        save_config
                        echo -e "${SW_GREEN}Clipboard tool updated to $clipboard_option.${SW_RESET}"
                        log "info" "Updated clipboard tool to $clipboard_option"
                    fi
                    
                    open_config_settings
                    ;;
                "Max History Size")
                    local max_history
                    max_history=$(gum input --prompt "Enter max history size: " --value "$MAX_HISTORY")
                    
                    if [[ "$max_history" =~ ^[0-9]+$ ]]; then
                        MAX_HISTORY="$max_history"
                        save_config
                        echo -e "${SW_GREEN}Max history size updated to $max_history.${SW_RESET}"
                        log "info" "Updated max history size to $max_history"
                    else
                        echo -e "${SW_RED}Invalid value. Please enter a number.${SW_RESET}"
                        log "error" "Invalid max history size: $max_history"
                    fi
                    
                    open_config_settings
                    ;;
                "Back")
                    open_config_settings
                    ;;
            esac
            ;;
        "Display Settings")
            local display_setting
            display_setting=$(gum choose \
                "Theme" \
                "Compact View" \
                "Log Level" \
                "Back")
            
            case "$display_setting" in
                "Theme")
                    local theme_option
                    theme_option=$(gum choose "synthwave" "dark" "light" "Back")
                    
                    if [[ "$theme_option" != "Back" ]]; then
                        THEME="$theme_option"
                        save_config
                        echo -e "${SW_GREEN}Theme updated to $theme_option.${SW_RESET}"
                        log "info" "Updated theme to $theme_option"
                    fi
                    
                    open_config_settings
                    ;;
                "Compact View")
                    local compact_option
                    compact_option=$(gum choose "true" "false" "Back")
                    
                    if [[ "$compact_option" != "Back" ]]; then
                        COMPACT_VIEW="$compact_option"
                        save_config
                        echo -e "${SW_GREEN}Compact view updated to $compact_option.${SW_RESET}"
                        log "info" "Updated compact view to $compact_option"
                    fi
                    
                    open_config_settings
                    ;;
                "Log Level")
                    local log_level_option
                    log_level_option=$(gum choose "debug" "info" "warn" "error" "Back")
                    
                    if [[ "$log_level_option" != "Back" ]]; then
                        LOG_LEVEL="$log_level_option"
                        save_config
                        echo -e "${SW_GREEN}Log level updated to $log_level_option.${SW_RESET}"
                        log "info" "Updated log level to $log_level_option"
                    fi
                    
                    open_config_settings
                    ;;
                "Back")
                    open_config_settings
                    ;;
            esac
            ;;
        "Notification Settings")
            local notification_setting
            notification_setting=$(gum choose \
                "Enable Notifications" \
                "Disable Notifications" \
                "Back")
            
            case "$notification_setting" in
                "Enable Notifications")
                    NOTIFICATION="true"
                    save_config
                    echo -e "${SW_GREEN}Notifications enabled.${SW_RESET}"
                    log "info" "Enabled notifications"
                    open_config_settings
                    ;;
                "Disable Notifications")
                    NOTIFICATION="false"
                    save_config
                    echo -e "${SW_GREEN}Notifications disabled.${SW_RESET}"
                    log "info" "Disabled notifications"
                    open_config_settings
                    ;;
                "Back")
                    open_config_settings
                    ;;
            esac
            ;;
        "App Helper Settings")
            manage_apps_menu
            open_config_settings
            ;;
        "Advanced Settings")
            local advanced_setting
            advanced_setting=$(gum choose \
                "View Logs" \
                "Clear Logs" \
                "Clear Clipboard History" \
                "Reset to Default Settings" \
                "Back")
            
            case "$advanced_setting" in
                "View Logs")
                    local log_file="${LOGS_DIR}/$(date +%Y-%m-%d).log"
                    
                    if [[ -f "$log_file" ]]; then
                        glow -s dark "$log_file"
                    else
                        echo -e "${SW_YELLOW}No logs found for today.${SW_RESET}"
                    fi
                    
                    open_config_settings
                    ;;
                "Clear Logs")
                    if gum confirm "Are you sure you want to clear all logs?"; then
                        rm -f "${LOGS_DIR}"/*.log
                        echo -e "${SW_GREEN}Logs cleared.${SW_RESET}"
                        log "info" "Cleared all logs"
                    fi
                    
                    open_config_settings
                    ;;
                "Clear Clipboard History")
                    if gum confirm "Are you sure you want to clear clipboard history?"; then
                        > "$HISTORY_FILE"
                        echo -e "${SW_GREEN}Clipboard history cleared.${SW_RESET}"
                        log "info" "Cleared clipboard history"
                    fi
                    
                    open_config_settings
                    ;;
                "Reset to Default Settings")
                    if gum confirm "Are you sure you want to reset to default settings?"; then
                        CLIPBOARD_TOOL="${DEFAULT_CLIPBOARD_TOOL}"
                        NOTIFICATION="${DEFAULT_NOTIFICATION}"
                        MAX_HISTORY="${DEFAULT_MAX_HISTORY}"
                        THEME="${DEFAULT_THEME}"
                        LOG_LEVEL="${DEFAULT_LOG_LEVEL}"
                        COMPACT_VIEW="${DEFAULT_COMPACT_VIEW}"
                        save_config
                        echo -e "${SW_GREEN}Settings reset to defaults.${SW_RESET}"
                        log "info" "Reset settings to defaults"
                    fi
                    
                    open_config_settings
                    ;;
                "Back")
                    open_config_settings
                    ;;
            esac
            ;;
        "Back to main menu")
            main_menu
            ;;
    esac
}

# Show help
show_help() {
    local help_markdown="# QBoss Help\n\n"
    help_markdown+="## Overview\n\n"
    help_markdown+="QBoss is a TUI script to explore and interact with KDE window manager using qdbus. It provides various features for listing, searching, and manipulating windows, as well as exploring DBus services.\n\n"
    
    help_markdown+="## Main Menu Options\n\n"
    help_markdown+="- **List Windows**: Show all windows with their IDs, classes, and titles.\n"
    help_markdown+="- **Search Windows**: Search for windows by class or title.\n"
    help_markdown+="- **List Window Classes**: Show all unique window classes and the number of windows for each.\n"
    help_markdown+="- **Get Clipboard History**: Show the history of items copied to clipboard.\n"
    help_markdown+="- **List DBus Services**: Show all available DBus services.\n"
    help_markdown+="- **Monitor Windows**: Monitor window creation and destruction in real-time.\n"
    help_markdown+="- **Capture Window on Click**: Click on a window to capture its properties.\n"
    help_markdown+="- **Execute Custom qdbus Command**: Run a custom qdbus command.\n"
    help_markdown+="- **Generate qdbus Shell Script**: Create a shell script for interacting with a window.\n"
    help_markdown+="- **App Helper**: Manage saved applications for quick access.\n"
    help_markdown+="- **Configuration Settings**: Configure QBoss settings.\n"
    help_markdown+="- **Check for Updates**: Check for updates to QBoss.\n"
    help_markdown+="- **Help**: Show this help.\n"
    help_markdown+="- **Exit**: Exit the script.\n\n"
    
    help_markdown+="## App Helper Feature\n\n"
    help_markdown+="The App Helper feature allows you to save frequently used applications and easily launch or toggle them.\n"
    help_markdown+="- Save an application by clicking on its window and selecting 'Save as application'\n"
    help_markdown+="- Launch a saved application with `$APP_NAME app-name`\n"
    help_markdown+="- If the application is already running, it will be activated or minimized/maximized\n"
    help_markdown+="- Manage saved applications in the App Helper menu\n\n"
    
    help_markdown+="## Command-Line Usage\n\n"
    help_markdown+="QBoss can also be used from the command line. Run \`$APP_NAME --help\` for more information.\n\n"
    
    help_markdown+="## Tips\n\n"
    help_markdown+="- Use Tab and arrow keys to navigate.\n"
    help_markdown+="- Press Enter to select an option.\n"
    help_markdown+="- Press Ctrl+C to exit a monitoring operation.\n"
    help_markdown+="- Use filter prompts to quickly find what you're looking for.\n"
    help_markdown+="- The clipboard history stores the last $MAX_HISTORY items.\n"
    help_markdown+="- Save frequently used applications for quick access with the App Helper.\n\n"
    
    help_markdown+="## GitHub Repository\n\n"
    help_markdown+="https://github.com/${GITHUB_REPO}\n\n"
    help_markdown+="Report issues, contribute, or check for updates at the GitHub repository.\n"
    
    create_temp_markdown "$help_markdown"
    log "info" "Displayed help information"
}

# Install QBoss to system
install_qboss() {
    echo -e "${SW_BOLD}Installing QBoss...${SW_RESET}"
    
    # Check if script is being run with sudo
    if [[ $EUID -ne 0 ]]; then
        echo -e "${SW_YELLOW}This operation requires administrator privileges.${SW_RESET}"
        echo "Please run the installation with sudo:"
        echo "  sudo $0 --install"
        return 1
    fi
    
    # Create directories if they don't exist
    mkdir -p "${INSTALL_DIR}"
    mkdir -p "${COMPLETION_DIR}"
    
    # Copy script to installation directory
    cp "$0" "${INSTALL_DIR}/${APP_NAME}"
    chmod +x "${INSTALL_DIR}/${APP_NAME}"
    
    # Create bash completion script
    cat > "${COMPLETION_DIR}/${APP_NAME}" << EOF
#!/bin/bash
# QBoss bash completion script

_qboss() {
    local cur prev opts
    COMPREPLY=()
    cur="\${COMP_WORDS[COMP_CWORD]}"
    prev="\${COMP_WORDS[COMP_CWORD-1]}"
    
    # Main options
    opts="--help --version --install --update --remove --config --theme --log-level --compact --no-color list search class info activate minimize maximize close monitor click service exec script copy apps app-save app-list app-delete"
    
    # Handle specific option arguments
    case "\${prev}" in
        --theme)
            COMPREPLY=( \$(compgen -W "synthwave dark light" -- "\${cur}") )
            return 0
            ;;
        --log-level)
            COMPREPLY=( \$(compgen -W "debug info warn error" -- "\${cur}") )
            return 0
            ;;
        search|class|service)
            # No specific completion for these
            return 0
            ;;
        info|activate|minimize|maximize|close|script)
            # Try to get window IDs
            if command -v qdbus >/dev/null 2>&1; then
                local window_ids=\$(qdbus org.kde.KWin /KWin org.kde.KWin.listWindows 2>/dev/null)
                COMPREPLY=( \$(compgen -W "\${window_ids}" -- "\${cur}") )
            fi
            return 0
            ;;
        copy)
            # Try to get window IDs
            if command -v qdbus >/dev/null 2>&1; then
                local window_ids=\$(qdbus org.kde.KWin /KWin org.kde.KWin.listWindows 2>/dev/null)
                COMPREPLY=( \$(compgen -W "\${window_ids}" -- "\${cur}") )
            fi
            return 0
            ;;
        app-delete)
            # Try to get saved app names
            if [ -f "${CONFIG_DIR}/apps.json" ]; then
                local app_names=\$(jq -r '.apps[].name' "${CONFIG_DIR}/apps.json" 2>/dev/null)
                COMPREPLY=( \$(compgen -W "\${app_names}" -- "\${cur}") )
            fi
            return 0
            ;;
        *)
            ;;
    esac
    
    # Check if we're completing the second argument for copy
    if [[ \${COMP_CWORD} -ge 3 && "\${COMP_WORDS[COMP_CWORD-2]}" == "copy" ]]; then
        COMPREPLY=( \$(compgen -W "id class title" -- "\${cur}") )
        return 0
    fi
    
    # If no option or command is typed yet, try to complete with app names
    if [[ \${COMP_CWORD} -eq 1 && \${cur} != -* ]]; then
        if [ -f "${CONFIG_DIR}/apps.json" ]; then
            local app_names=\$(jq -r '.apps[].name' "${CONFIG_DIR}/apps.json" 2>/dev/null)
            COMPREPLY=( \$(compgen -W "\${app_names}" -- "\${cur}") )
            if [[ -n "\${COMPREPLY}" ]]; then
                # App name matches found, return
                return 0
            fi
        fi
    fi
    
    # Default completion for options
    if [[ \${cur} == -* ]]; then
        COMPREPLY=( \$(compgen -W "--help --version --install --update --remove --config --theme --log-level --compact --no-color" -- "\${cur}") )
    else
        COMPREPLY=( \$(compgen -W "list search class info activate minimize maximize close monitor click service exec script copy apps app-save app-list app-delete" -- "\${cur}") )
    fi
    
    return 0
}

complete -F _qboss qboss
EOF
    
    # Create desktop entry
    mkdir -p /usr/local/share/applications
    cat > /usr/local/share/applications/${APP_NAME}.desktop << EOF
[Desktop Entry]
Name=QBoss
Comment=KDE Window Manager TUI
Exec=${INSTALL_DIR}/${APP_NAME}
Icon=preferences-system-windows
Terminal=true
Type=Application
Categories=Utility;System;
Keywords=KDE;Window;Manager;qdbus;
EOF
    
    echo -e "${SW_GREEN}QBoss has been installed successfully!${SW_RESET}"
    echo "You can now run '${APP_NAME}' from anywhere."
    echo "Desktop entry and bash completion have been added."
    
    return 0
}

# Update QBoss from GitHub
update_qboss() {
    echo -e "${SW_BOLD}Checking for updates...${SW_RESET}"
    
    # Get current script path
    local script_path
    if [[ -L "$0" ]]; then
        script_path=$(readlink -f "$0")
    else
        script_path="$0"
    fi
    
    # Check if we can write to the script path
    if [[ ! -w "$script_path" ]]; then
        echo -e "${SW_YELLOW}You don't have permission to update QBoss.${SW_RESET}"
        echo "Please run the update with sudo:"
        echo "  sudo $0 --update"
        return 1
    fi
    
    # Fetch latest version from GitHub
    local latest_version
    latest_version=$(curl -s "https://raw.githubusercontent.com/${GITHUB_REPO}/main/version.txt" 2>/dev/null)
    
    if [[ -z "$latest_version" ]]; then
        echo -e "${SW_RED}Failed to fetch latest version.${SW_RESET}"
        log "error" "Failed to fetch latest version from GitHub"
        return 1
    fi
    
    # Compare versions
    if [[ "$latest_version" == "$VERSION" ]]; then
        echo -e "${SW_GREEN}QBoss is already up to date (v${VERSION}).${SW_RESET}"
        log "info" "QBoss is already up to date (v${VERSION})"
        return 0
    fi
    
    echo -e "${SW_YELLOW}New version available: v${latest_version}${SW_RESET}"
    echo -e "Current version: v${VERSION}"
    
    # In interactive mode, ask for confirmation
    if [[ -z "${CLI_MODE:-}" ]]; then
        if ! gum confirm "Do you want to update to the latest version?"; then
            echo -e "${SW_YELLOW}Update canceled.${SW_RESET}"
            log "info" "Update canceled by user"
            return 0
        fi
    fi
    
    # Download the latest version from GitHub
    echo "Downloading latest version..."
    local temp_file
    temp_file=$(mktemp)
    
    if ! curl -s "$GITHUB_RAW_URL" -o "$temp_file"; then
        echo -e "${SW_RED}Failed to download latest version.${SW_RESET}"
        log "error" "Failed to download latest version from GitHub"
        rm -f "$temp_file"
        return 1
    fi
    
    # Make backup of current version
    local backup_file="${script_path}.backup"
    cp "$script_path" "$backup_file"
    
    # Update the script
    cat "$temp_file" > "$script_path"
    chmod +x "$script_path"
    rm -f "$temp_file"
    
    echo -e "${SW_GREEN}QBoss has been updated to v${latest_version}.${SW_RESET}"
    echo "A backup of the previous version has been saved to: $backup_file"
    log "info" "Updated QBoss from v${VERSION} to v${latest_version}"
    
    echo "Please restart QBoss for the changes to take effect."
    
    return 0
}

# Check for updates without installing
check_for_updates() {
    echo -e "${SW_BOLD}Checking for updates...${SW_RESET}"
    
    # Fetch latest version from GitHub
    local latest_version
    latest_version=$(curl -s "https://raw.githubusercontent.com/${GITHUB_REPO}/main/version.txt" 2>/dev/null)
    
    if [[ -z "$latest_version" ]]; then
        echo -e "${SW_RED}Failed to fetch latest version.${SW_RESET}"
        log "error" "Failed to fetch latest version from GitHub"
        return 1
    fi
    
    # Compare versions
    if [[ "$latest_version" == "$VERSION" ]]; then
        echo -e "${SW_GREEN}QBoss is up to date (v${VERSION}).${SW_RESET}"
        log "info" "QBoss is up to date (v${VERSION})"
    else
        echo -e "${SW_YELLOW}New version available: v${latest_version}${SW_RESET}"
        echo -e "Current version: v${VERSION}"
        echo "Run '${APP_NAME} --update' to update."
        log "info" "New version available: v${latest_version}"
    fi
    
    return 0
}

# Remove QBoss from system
remove_qboss() {
    echo -e "${SW_BOLD}Removing QBoss...${SW_RESET}"
    
    # Check if script is being run with sudo
    if [[ $EUID -ne 0 ]]; then
        echo -e "${SW_YELLOW}This operation requires administrator privileges.${SW_RESET}"
        echo "Please run the removal with sudo:"
        echo "  sudo $0 --remove"
        return 1
    fi
    
    # In interactive mode, ask for confirmation
    if [[ -z "${CLI_MODE:-}" ]]; then
        if ! gum confirm "Are you sure you want to remove QBoss from your system?"; then
            echo -e "${SW_YELLOW}Removal canceled.${SW_RESET}"
            return 0
        fi
    fi
    
    # Remove executable
    if [[ -f "${INSTALL_DIR}/${APP_NAME}" ]]; then
        rm -f "${INSTALL_DIR}/${APP_NAME}"
    fi
    
    # Remove bash completion
    if [[ -f "${COMPLETION_DIR}/${APP_NAME}" ]]; then
        rm -f "${COMPLETION_DIR}/${APP_NAME}"
    fi
    
    # Remove desktop entry
    if [[ -f "/usr/local/share/applications/${APP_NAME}.desktop" ]]; then
        rm -f "/usr/local/share/applications/${APP_NAME}.desktop"
    fi
    
    # Ask if user wants to remove config files
    local remove_config=false
    
    if [[ -z "${CLI_MODE:-}" ]]; then
        if gum confirm "Do you want to remove configuration files as well?"; then
            remove_config=true
        fi
    fi
    
    if [[ "$remove_config" == true ]]; then
        if [[ -d "${CONFIG_DIR}" ]]; then
            rm -rf "${CONFIG_DIR}"
        fi
        echo -e "${SW_GREEN}QBoss has been completely removed from your system.${SW_RESET}"
    else
        echo -e "${SW_GREEN}QBoss has been removed, but configuration files have been kept.${SW_RESET}"
        echo "Configuration files are located at: ${CONFIG_DIR}"
    fi
    
    return 0
}

# Save app configuration
save_app_config() {
    local app_name="$1"
    local window_id="$2"
    
    if [[ -z "$app_name" ]]; then
        echo -e "${SW_YELLOW}App name cannot be empty.${SW_RESET}"
        log "warn" "App name cannot be empty"
        return 1
    fi
    
    if [[ -z "$window_id" ]]; then
        echo -e "${SW_YELLOW}Window ID cannot be empty.${SW_RESET}"
        log "warn" "Window ID cannot be empty for app configuration"
        return 1
    fi
    
    # Get window class and title
    local class
    class=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowClass "$window_id" 2>/dev/null) || class="N/A"
    
    local title
    title=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowTitle "$window_id" 2>/dev/null) || title="N/A"
    
    # Find the desktop file
    local desktop_file=""
    if command -v find &> /dev/null; then
        # Search in common locations for desktop files
        for location in "/usr/share/applications" "/usr/local/share/applications" "$HOME/.local/share/applications"; do
            if [[ -d "$location" ]]; then
                # Try to find desktop file by class name or by window title
                local found_file
                found_file=$(find "$location" -name "*$class*.desktop" -o -name "*$(echo "$title" | cut -d' ' -f1)*.desktop" 2>/dev/null | head -n 1)
                
                if [[ -n "$found_file" ]]; then
                    desktop_file=$(basename "$found_file")
                    break
                fi
            fi
        done
    fi
    
    # If no desktop file found, try to guess it from the class
    if [[ -z "$desktop_file" ]]; then
        desktop_file="${class,,}.desktop"
    fi
    
    # Create app data structure
    local app_data="{
        \"name\": \"$app_name\",
        \"class\": \"$class\",
        \"title\": \"$title\",
        \"desktop_file\": \"$desktop_file\"
    }"
    
    # Make sure the apps config file exists
    if [[ ! -f "${APPS_CONFIG_FILE}" ]]; then
        echo "{\"apps\": []}" > "${APPS_CONFIG_FILE}"
    fi
    
    # Check if the app already exists
    local existing_app_index
    existing_app_index=$(jq -r --arg name "$app_name" '.apps | map(.name == $name) | index(true) // "null"' "${APPS_CONFIG_FILE}" 2>/dev/null || echo "null")
    
    if [[ "$existing_app_index" != "null" ]]; then
        # Update existing app
        jq --argjson idx "$existing_app_index" --argjson app "$app_data" '.apps[$idx] = $app' "${APPS_CONFIG_FILE}" > "${APPS_CONFIG_FILE}.tmp"
        mv "${APPS_CONFIG_FILE}.tmp" "${APPS_CONFIG_FILE}"
        echo -e "${SW_GREEN}Updated app:${SW_RESET} $app_name"
        show_notification "Updated app: $app_name"
        log "info" "Updated app: $app_name with class $class"
    else
        # Add new app
        jq --argjson app "$app_data" '.apps += [$app]' "${APPS_CONFIG_FILE}" > "${APPS_CONFIG_FILE}.tmp"
        mv "${APPS_CONFIG_FILE}.tmp" "${APPS_CONFIG_FILE}"
        echo -e "${SW_GREEN}Saved app:${SW_RESET} $app_name"
        show_notification "Saved app: $app_name"
        log "info" "Saved app: $app_name with class $class"
    fi
    
    return 0
}

# List saved apps
list_apps() {
    # Make sure the apps config file exists
    if [[ ! -f "${APPS_CONFIG_FILE}" ]]; then
        echo "{\"apps\": []}" > "${APPS_CONFIG_FILE}"
    fi
    
    local apps_count
    apps_count=$(jq '.apps | length' "${APPS_CONFIG_FILE}" 2>/dev/null || echo "0")
    
    if [[ "$apps_count" -eq 0 ]]; then
        echo -e "${SW_YELLOW}No saved applications found.${SW_RESET}"
        log "info" "No saved applications found"
        return 0
    fi
    
    local markdown="# Saved Applications\n\n"
    markdown+="| # | Name | Class | Desktop File |\n"
    markdown+="|:--|:-----|:------|:------------|\n"
    
    local i=0
    while [[ $i -lt $apps_count ]]; do
        local name
        local class
        local desktop_file
        
        name=$(jq -r ".apps[$i].name" "${APPS_CONFIG_FILE}")
        class=$(jq -r ".apps[$i].class" "${APPS_CONFIG_FILE}")
        desktop_file=$(jq -r ".apps[$i].desktop_file" "${APPS_CONFIG_FILE}")
        
        markdown+="| $((i+1)) | $name | $class | $desktop_file |\n"
        ((i++))
    done
    
    markdown+="\n\n$apps_count application(s) found."
    markdown+="\n\nUse \`$APP_NAME <app-name>\` to launch or toggle an application."
    
    create_temp_markdown "$markdown"
    log "info" "Listed $apps_count saved applications"
    
    return 0
}

# Delete a saved app
delete_app() {
    local app_name="$1"
    
    if [[ -z "$app_name" ]]; then
        if [[ -z "${CLI_MODE:-}" ]]; then
            # List apps and let user select one to delete
            local apps_count
            apps_count=$(jq '.apps | length' "${APPS_CONFIG_FILE}" 2>/dev/null || echo "0")
            
            if [[ "$apps_count" -eq 0 ]]; then
                echo -e "${SW_YELLOW}No saved applications found.${SW_RESET}"
                log "info" "No saved applications found"
                return 0
            fi
            
            local options=()
            local i=0
            while [[ $i -lt $apps_count ]]; do
                local name
                name=$(jq -r ".apps[$i].name" "${APPS_CONFIG_FILE}")
                options+=("$name")
                ((i++))
            done
            
            app_name=$(printf "%s\n" "${options[@]}" | gum filter --prompt "Select an app to delete: ")
        else
            echo -e "${SW_YELLOW}App name cannot be empty.${SW_RESET}"
            log "warn" "App name cannot be empty for delete operation"
            return 1
        fi
    fi
    
    if [[ -z "$app_name" ]]; then
        echo -e "${SW_YELLOW}No app selected.${SW_RESET}"
        log "warn" "No app selected for delete operation"
        return 1
    fi
    
    # Check if the app exists
    local existing_app_index
    existing_app_index=$(jq -r --arg name "$app_name" '.apps | map(.name == $name) | index(true) // "null"' "${APPS_CONFIG_FILE}" 2>/dev/null || echo "null")
    
    if [[ "$existing_app_index" == "null" ]]; then
        echo -e "${SW_RED}App not found:${SW_RESET} $app_name"
        log "error" "App not found for delete operation: $app_name"
        return 1
    fi
    
    # Confirm deletion in interactive mode
    if [[ -z "${CLI_MODE:-}" ]]; then
        if ! gum confirm "Are you sure you want to delete app '$app_name'?"; then
            echo -e "${SW_YELLOW}Deletion canceled.${SW_RESET}"
            log "info" "App deletion canceled by user: $app_name"
            return 0
        fi
    fi
    
    # Delete the app
    jq --argjson idx "$existing_app_index" '.apps = .apps[0:$idx] + .apps[$idx+1:]' "${APPS_CONFIG_FILE}" > "${APPS_CONFIG_FILE}.tmp"
    mv "${APPS_CONFIG_FILE}.tmp" "${APPS_CONFIG_FILE}"
    
    echo -e "${SW_GREEN}Deleted app:${SW_RESET} $app_name"
    show_notification "Deleted app: $app_name"
    log "info" "Deleted app: $app_name"
    
    return 0
}

# Manage apps menu
manage_apps_menu() {
    local action
    action=$(gum choose \
        "List Saved Apps" \
        "Save App from Click" \
        "Delete App" \
        "Test App Launch" \
        "Back")
    
    case "$action" in
        "List Saved Apps")
            list_apps
            manage_apps_menu
            ;;
        "Save App from Click")
            echo -e "${SW_BLUE}Click on a window to save as an app...${SW_RESET}"
            log "info" "Started window capture for app save"
            
            local pid
            pid=$(xdotool selectwindow getwindowpid 2>/dev/null)
            
            if [[ -z "$pid" ]]; then
                echo -e "${SW_RED}Failed to capture window. Make sure xdotool is installed.${SW_RESET}"
                log "error" "Failed to capture window with xdotool"
                manage_apps_menu
                return 1
            fi
            
            # Try to find the window ID from PID
            local window_ids
            window_ids=$(get_window_list)
            
            for id in $window_ids; do
                local window_pid
                window_pid=$(xprop -id "$id" _NET_WM_PID 2>/dev/null | cut -d' ' -f3)
                
                if [[ "$window_pid" == "$pid" ]]; then
                    log "info" "Captured window ID $id for app save"
                    
                    local class
                    class=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowClass "$id" 2>/dev/null) || class="N/A"
                    
                    local title
                    title=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowTitle "$id" 2>/dev/null) || title="N/A"
                    
                    # Ask for app name
                    local app_name
                    app_name=$(gum input --prompt "Enter a name for this application: " --value "$class")
                    
                    if [[ -n "$app_name" ]]; then
                        save_app_config "$app_name" "$id"
                    else
                        echo -e "${SW_YELLOW}App name cannot be empty.${SW_RESET}"
                        log "warn" "App name cannot be empty"
                    fi
                    
                    manage_apps_menu
                    return 0
                fi
            done
            
            echo -e "${SW_YELLOW}Could not find KWin window ID for process ID $pid.${SW_RESET}"
            log "warn" "Could not find KWin window ID for process ID $pid"
            manage_apps_menu
            ;;
        "Delete App")
            # List apps and let user select one to delete
            delete_app ""
            manage_apps_menu
            ;;
        "Test App Launch")
            # List apps and let user select one to launch
            local apps_count
            apps_count=$(jq '.apps | length' "${APPS_CONFIG_FILE}" 2>/dev/null || echo "0")
            
            if [[ "$apps_count" -eq 0 ]]; then
                echo -e "${SW_YELLOW}No saved applications found.${SW_RESET}"
                log "info" "No saved applications found"
                manage_apps_menu
                return 0
            fi
            
            local options=()
            local i=0
            while [[ $i -lt $apps_count ]]; do
                local name
                name=$(jq -r ".apps[$i].name" "${APPS_CONFIG_FILE}")
                options+=("$name")
                ((i++))
            done
            
            local selected_app
            selected_app=$(printf "%s\n" "${options[@]}" | gum filter --prompt "Select an app to launch: ")
            
            if [[ -n "$selected_app" ]]; then
                launch_app "$selected_app"
            fi
            
            manage_apps_menu
            ;;
        "Back")
            return 0
            ;;
    esac
}

# Launch or toggle an app
launch_app() {
    local app_name="$1"
    
    if [[ -z "$app_name" ]]; then
        echo -e "${SW_YELLOW}App name cannot be empty.${SW_RESET}"
        log "warn" "App name cannot be empty for launch operation"
        return 1
    fi
    
    # Check if the app exists
    local app_exists
    app_exists=$(jq -r --arg name "$app_name" '.apps | map(select(.name == $name)) | length' "${APPS_CONFIG_FILE}" 2>/dev/null || echo "0")
    
    if [[ "$app_exists" -eq 0 ]]; then
        echo -e "${SW_RED}App not found:${SW_RESET} $app_name"
        log "error" "App not found for launch operation: $app_name"
        return 1
    fi
    
    # Get app details
    local class
    local desktop_file
    
    class=$(jq -r --arg name "$app_name" '.apps[] | select(.name == $name) | .class' "${APPS_CONFIG_FILE}")
    desktop_file=$(jq -r --arg name "$app_name" '.apps[] | select(.name == $name) | .desktop_file' "${APPS_CONFIG_FILE}")
    
    # Try to find a window with the matching class
    local window_ids
    window_ids=$(get_window_list)
    
    local matching_window=""
    
    for id in $window_ids; do
        local window_class
        window_class=$(qdbus org.kde.KWin /KWin org.kde.KWin.windowClass "$id" 2>/dev/null) || window_class=""
        
        if [[ "$window_class" == "$class" ]]; then
            matching_window="$id"
            break
        fi
    done
    
    if [[ -n "$matching_window" ]]; then
        # Window exists, check its state
        local is_minimized
        is_minimized=$(qdbus org.kde.KWin /KWin org.kde.KWin.isMinimized "$matching_window" 2>/dev/null) || is_minimized="false"
        
        # Toggle window state
        if [[ "$is_minimized" == "true" ]]; then
            # Unminimize and activate
            qdbus org.kde.KWin /KWin org.kde.KWin.unminimizeWindow "$matching_window" &>/dev/null
            qdbus org.kde.KWin /KWin org.kde.KWin.setCurrentWindow "$matching_window" &>/dev/null
            
            show_notification "App activated: $app_name"
            log "info" "Activated app: $app_name (window ID: $matching_window)"
        else
            # Minimize
            qdbus org.kde.KWin /KWin org.kde.KWin.minimizeWindow "$matching_window" &>/dev/null
            
            show_notification "App minimized: $app_name"
            log "info" "Minimized app: $app_name (window ID: $matching_window)"
        fi
    else
        # Window doesn't exist, launch the app using its desktop file
        if [[ -n "$desktop_file" ]]; then
            if gtk-launch "${desktop_file%.desktop}" &>/dev/null; then
                show_notification "App launched: $app_name"
                log "info" "Launched app: $app_name (desktop file: $desktop_file)"
            else
                echo -e "${SW_RED}Failed to launch app:${SW_RESET} $app_name"
                log "error" "Failed to launch app: $app_name (desktop file: $desktop_file)"
                return 1
            fi
        else
            echo -e "${SW_RED}No desktop file found for app:${SW_RESET} $app_name"
            log "error" "No desktop file found for app: $app_name"
            return 1
        fi
    fi
    
    return 0
}

# Save app from commandline click
save_app_from_click() {
    local app_name="$1"
    
    if [[ -z "$app_name" ]]; then
        echo -e "${SW_YELLOW}App name cannot be empty.${SW_RESET}"
        log "warn" "App name cannot be empty for save operation"
        return 1
    fi
    
    echo -e "${SW_BLUE}Click on a window to save as '$app_name'...${SW_RESET}"
    log "info" "Started window capture for app save: $app_name"
    
    local pid
    pid=$(xdotool selectwindow getwindowpid 2>/dev/null)
    
    if [[ -z "$pid" ]]; then
        echo -e "${SW_RED}Failed to capture window. Make sure xdotool is installed.${SW_RESET}"
        log "error" "Failed to capture window with xdotool"
        return 1
    fi
    
    # Try to find the window ID from PID
    local window_ids
    window_ids=$(get_window_list)
    
    for id in $window_ids; do
        local window_pid
        window_pid=$(xprop -id "$id" _NET_WM_PID 2>/dev/null | cut -d' ' -f3)
        
        if [[ "$window_pid" == "$pid" ]]; then
            log "info" "Captured window ID $id for app save: $app_name"
            save_app_config "$app_name" "$id"
            return 0
        fi
    done
    
    echo -e "${SW_YELLOW}Could not find KWin window ID for process ID $pid.${SW_RESET}"
    log "warn" "Could not find KWin window ID for process ID $pid"
    return 1
}

# Command-line interface
cli_interface() {
    local command="$1"
    shift
    
    case "$command" in
        list)
            list_windows
            ;;
        search)
            local term="$1"
            search_windows "$term"
            ;;
        class)
            local filter="$1"
            list_window_classes "$filter"
            ;;
        info)
            local window_id="$1"
            if [[ -z "$window_id" ]]; then
                echo -e "${SW_YELLOW}Window ID required.${SW_RESET}"
                return 1
            fi
            get_window_info "$window_id"
            ;;
        activate)
            local window_id="$1"
            activate_window "$window_id"
            ;;
        minimize)
            local window_id="$1"
            minimize_window "$window_id"
            ;;
        maximize)
            local window_id="$1"
            maximize_window "$window_id"
            ;;
        close)
            local window_id="$1"
            close_window "$window_id"
            ;;
        monitor)
            monitor_windows
            ;;
        click)
            capture_window_on_click
            ;;
        service)
            local filter="$1"
            list_qdbus_services "$filter"
            ;;
        exec)
            local cmd="$*"
            execute_custom_qdbus "$cmd"
            ;;
        script)
            local window_id="$1"
            generate_qdbus_script "$window_id"
            ;;
        copy)
            local window_id="$1"
            local property="$2"
            if [[ -z "$window_id" || -z "$property" ]]; then
                echo -e "${SW_YELLOW}Window ID and property type required.${SW_RESET}"
                echo "Usage: $APP_NAME copy <window_id> <id|class|title>"
                return 1
            fi
            copy_window_property "$window_id" "$property"
            ;;
        apps)
            manage_apps_menu
            ;;
        app-save)
            local app_name="$1"
            save_app_from_click "$app_name"
            ;;
        app-list)
            list_apps
            ;;
        app-delete)
            local app_name="$1"
            delete_app "$app_name"
            ;;
        *)
            # Check if command is a saved app name
            if [[ -f "${APPS_CONFIG_FILE}" ]]; then
                local app_exists
                app_exists=$(jq -r --arg name "$command" '.apps | map(select(.name == $name)) | length' "${APPS_CONFIG_FILE}" 2>/dev/null)
                
                if [[ "$app_exists" -gt 0 ]]; then
                    launch_app "$command"
                    return $?
                fi
            fi
            
            echo -e "${SW_YELLOW}Unknown command: $command${SW_RESET}"
            print_usage
            return 1
            ;;
    esac
    
    return 0
}

# Main menu function
main_menu() {
    while true; do
        local action
        action=$(gum choose \
            "List Windows" \
            "Search Windows" \
            "List Window Classes" \
            "Get Clipboard History" \
            "List DBus Services" \
            "Monitor Windows" \
            "Capture Window on Click" \
            "Execute Custom qdbus Command" \
            "Generate qdbus Shell Script" \
            "App Helper" \
            "Configuration Settings" \
            "Check for Updates" \
            "Help" \
            "Exit")
        
        case "$action" in
            "List Windows")
                list_windows
                ;;
            "Search Windows")
                search_windows ""
                ;;
            "List Window Classes")
                list_window_classes ""
                ;;
            "Get Clipboard History")
                get_clipboard_history
                ;;
            "List DBus Services")
                list_qdbus_services ""
                ;;
            "Monitor Windows")
                monitor_windows
                ;;
            "Capture Window on Click")
                capture_window_on_click
                ;;
            "Execute Custom qdbus Command")
                execute_custom_qdbus ""
                ;;
            "Generate qdbus Shell Script")
                generate_qdbus_script ""
                ;;
            "App Helper")
                manage_apps_menu
                ;;
            "Configuration Settings")
                open_config_settings
                ;;
            "Check for Updates")
                check_for_updates
                ;;
            "Help")
                show_help
                ;;
            "Exit")
                echo -e "${SW_GREEN}Exiting QBoss. Goodbye!${SW_RESET}"
                exit 0
                ;;
        esac
    done
}

# Main function
main() {
    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi
    
    # Create default config if it doesn't exist
    create_default_config
    
    # Load configuration
    load_config
    
    # Process command-line arguments
    if [[ $# -gt 0 ]]; then
        CLI_MODE=true
        
        case "$1" in
            -h|--help)
                print_usage
                ;;
            -v|--version)
                print_version
                ;;
            -i|--install)
                install_qboss
                ;;
            -u|--update)
                update_qboss
                ;;
            -r|--remove)
                remove_qboss
                ;;
            -c|--config)
                shift
                open_config_settings
                ;;
            -t|--theme)
                if [[ -n "$2" ]]; then
                    THEME="$2"
                    save_config
                    echo -e "${SW_GREEN}Theme set to $THEME.${SW_RESET}"
                    shift 2
                else
                    echo -e "${SW_RED}Error: Theme name required.${SW_RESET}"
                    exit 1
                fi
                ;;
            -l|--log-level)
                if [[ -n "$2" ]]; then
                    LOG_LEVEL="$2"
                    save_config
                    echo -e "${SW_GREEN}Log level set to $LOG_LEVEL.${SW_RESET}"
                    shift 2
                else
                    echo -e "${SW_RED}Error: Log level required.${SW_RESET}"
                    exit 1
                fi
                ;;
            --compact)
                COMPACT_VIEW="true"
                save_config
                echo -e "${SW_GREEN}Compact view enabled.${SW_RESET}"
                shift
                ;;
            --no-color)
                # Disable all color codes
                SW_MAGENTA=''
                SW_CYAN=''
                SW_BLUE=''
                SW_PURPLE=''
                SW_PINK=''
                SW_YELLOW=''
                SW_ORANGE=''
                SW_GREEN=''
                SW_RED=''
                SW_BG=''
                SW_BLACK=''
                SW_BOLD=''
                SW_RESET=''
                shift
                ;;
            *)
                cli_interface "$@"
                exit $?
                ;;
        esac
    else
        # Interactive mode
        print_logo
        
        # Check for KWin DBus interface
        check_kwin_dbus
        
        main_menu
    fi
}

# Run main function
main "$@"
        #