#!/usr/bin/env sh

if [ -z  "$1" ]; then
    export PREFIX=/usr
    # Make sure only root can run our script
    if [ "$(id -u)" != "0" ]; then
        echo "This script must be run as root" 1>&2
        exit 1
    fi
else
    export PREFIX=$1
fi

echo "Uninstalling from prefix ${PREFIX}"

rm ${PREFIX}/bin/aiterm
rm ${PREFIX}/share/glib-2.0/schemas/com.aiterm.Aiterm.gschema.xml
glib-compile-schemas ${PREFIX}/share/glib-2.0/schemas/
rm -rf ${PREFIX}/share/aiterm

find ${PREFIX}/share/locale -type f -name "aiterm.mo" -delete
find ${PREFIX}/share/icons/hicolor -type f -name "com.aiterm.Aiterm.png" -delete
find ${PREFIX}/share/icons/hicolor -type f -name "com.aiterm.Aiterm*.svg" -delete
rm ${PREFIX}/share/nautilus-python/extensions/open-aiterm.py
rm ${PREFIX}/share/dbus-1/services/com.aiterm.Aiterm.service
rm ${PREFIX}/share/applications/com.aiterm.Aiterm.desktop
rm ${PREFIX}/share/metainfo/com.aiterm.Aiterm.appdata.xml
rm ${PREFIX}/share/man/man1/aiterm.1.gz
rm ${PREFIX}/share/man/*/man1/aiterm.1.gz
