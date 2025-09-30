#!/bin/bash

set -e  # Stops the scripts in case of an error

APP_NAME="work_manager"
INSTALL_DIR="$HOME/work_manager"
work_manager_name="wmanager"

# Create the installation directory
if [ ! -d $INSTALL_DIR ]; then
  mkdir -p "$INSTALL_DIR"
fi

# Copies the files
cp "$APP_NAME" "$INSTALL_DIR/"

# Detects the configuration file of the shell
if [[ -f "$HOME/.zshrc" ]]; then
    SHELL_RC="$HOME/.zshrc"
    SHELL_NAME="zsh"
elif [[ -f "$HOME/.bashrc" ]]; then
    SHELL_RC="$HOME/.bashrc"
    SHELL_NAME="bash"
else
    echo "Unknown shell configuration"
    exit 1
fi

echo "Detect shell config file: $SHELL_RC (Shell : $SHELL_NAME)"
# Ajout de l'alias si pas encore présent
if grep -q "alias $work_manager_name=" "$SHELL_RC"; then
    echo "Alias '$work_manager_name' exists already in $SHELL_RC. No changes were applied"
else
    echo "Adding the alias in $SHELL_RC..."
    echo "" >> "$SHELL_RC"
    echo "# Alias work_manager" >> "$SHELL_RC"
      echo "alias $work_manager_name=\"$INSTALL_DIR/$APP_NAME\"" >> "$SHELL_RC"
    echo "Alias added !"
fi

echo ""
echo "👉 Reload your shell by typing the command : source $SHELL_RC"
echo "   Or restart your terminal."
