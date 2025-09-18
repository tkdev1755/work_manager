#!/bin/bash

OS=$1
ARCH=$2
# Nom de l'archive de sortie
OUTPUT="workManager_${OS}_${ARCH}.zip"

# Fichiers à inclure
FILES=("bin/work_manager" "buildAssets/install.sh")

# Vérification que les fichiers existent
for FILE in "${FILES[@]}"; do
    if [[ ! -f "$FILE" ]]; then
        echo "Erreur : le fichier $FILE n'existe pas."
        exit 1
    fi
done

# Création de l'archive ZIP
zip "$OUTPUT" "${FILES[@]}"

# Message de confirmation
if [[ $? -eq 0 ]]; then
    echo "✅ Archive créée avec succès : $OUTPUT"
else
    echo "❌ Erreur lors de la création de l'archive."
fi

