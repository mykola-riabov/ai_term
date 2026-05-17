# Resets Aiterm settings to default for testing purposes
gsettings list-schemas | grep Aiterm | xargs -n 1 gsettings reset-recursively
dconf list /com/aiterm/Aiterm/profiles/ | xargs -I {} dconf reset -f "/com/aiterm/Aiterm/profiles/"{}
