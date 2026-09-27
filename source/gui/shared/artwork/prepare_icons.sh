#!/bin/sh
# Prepare platform masters from the original artwork using ImageMagick 7.
set -eu
cd "$(dirname "$0")"

source_image=RetroDLP-source.png

# Preserve the complete source canvas and alpha for macOS. No crop or mask.
cp "$source_image" RetroDLP-macOS.png

# iOS requires an opaque icon. Composite the full artwork onto white without
# changing its size, proportions, or placement.
magick "$source_image" -background white -alpha remove -alpha off \
    -depth 8 PNG24:RetroDLP-iOS.png
