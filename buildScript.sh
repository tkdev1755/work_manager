#!/bin/bash
VERSION=$1
OS=$2
ARCH=$3
# Nom de l'archive de sortie
dart compile exe bin/work_manager.dart
if ! [[ "$OS" = "windows" ]]; then
  cp bin/work_manager.exe bin/work_manager
fi

mkdir -p releases/"$VERSION"/"${OS}_$ARCH"/
# shellcheck disable=SC2086

cp bin/work_manager releases/$VERSION/"${OS}_$ARCH"/
# shellcheck disable=SC2086
cp buildAssets/install.sh releases/$VERSION/"${OS}_$ARCH"/
OUTPUT="workManager_${OS}_${ARCH}.zip"


# Création de l'archive ZIP
cd releases/"$VERSION"/"${OS}_$ARCH" || exit
if [[ "$OS" = "windows" ]]; then
    powershell.exe -Command "Compress-Archive -Path * -DestinationPath $OUTPUT -Force"
	  echo "Zipped the archive correctly"
else
	zip -r "$OUTPUT" .
fi


# Message de confirmation
if [[ $? -eq 0 ]]; then
    echo "✅ Archive créée avec succès : $OUTPUT"
else
    echo "❌ Erreur lors de la création de l'archive."
fi

