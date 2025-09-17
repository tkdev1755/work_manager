#!/bin/bash

set -e  # Arrêter le script en cas d'erreur

APP_NAME="work_manager"
INSTALL_DIR="$HOME/work_manager"
work_manager_name="wmanager"

# Création du dossier d'installation
if [ ! -d $INSTALL_DIR ]; then
  mkdir -p "$INSTALL_DIR"
fi

# Copie des fichiers
cp "$APP_NAME" "$INSTALL_DIR/"

# Détection du fichier de configuration du shell
if [[ -f "$HOME/.zshrc" ]]; then
    SHELL_RC="$HOME/.zshrc"
    SHELL_NAME="zsh"
elif [[ -f "$HOME/.bashrc" ]]; then
    SHELL_RC="$HOME/.bashrc"
    SHELL_NAME="bash"
else
    echo "Configuration shell inconnue"
    exit 1
fi

echo "Fichier de configuration détecté : $SHELL_RC (Shell : $SHELL_NAME)"
# Ajout de l'alias si pas encore présent
if grep -q "alias $work_manager_name=" "$SHELL_RC"; then
    echo "Alias '$work_manager_name' déjà existant dans $SHELL_RC. Aucune modification n'as été apportée"
else
    echo "Ajout de l'alias dans $SHELL_RC..."
    echo "" >> "$SHELL_RC"
    echo "# Alias work_manager" >> "$SHELL_RC"
      echo "alias $work_manager_name=\"$INSTALL_DIR/$APP_NAME\"" >> "$SHELL_RC"
    echo "Alias ajouté !"
fi

echo ""
echo "👉 Rechargez votre shell en tapant la commande : source $SHELL_RC"
echo "   Ou redémarrez votre terminal."
