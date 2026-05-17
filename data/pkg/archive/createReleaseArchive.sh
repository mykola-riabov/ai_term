export AITERM_ARCHIVE_PATH="/tmp/aiterm/archive";

rm -rf ${AITERM_ARCHIVE_PATH}

CURRENT_DIR=$(pwd)

echo "Building application..."
cd ../../..
dub build --build=release --compiler=ldc2
strip aiterm

./install.sh ${AITERM_ARCHIVE_PATH}/usr

# Remove compiled schema
rm ${AITERM_ARCHIVE_PATH}/usr/share/glib-2.0/schemas/gschemas.compiled

echo "Creating archive"
cd ${AITERM_ARCHIVE_PATH}
zip -r aiterm.zip *

cp aiterm.zip ${CURRENT_DIR}/aiterm.zip
cd ${CURRENT_DIR}
