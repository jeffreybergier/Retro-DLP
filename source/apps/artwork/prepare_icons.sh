#!/bin/sh
# Prepare platform masters from the original artwork using ImageMagick 7.
set -eu
cd "$(dirname "$0")"

source_image=RetroDLP-source.png
if [ "$(magick identify -format '%wx%h' "$source_image")" != 1254x1254 ]; then
    echo 'The mask and crop require the original 1254x1254 artwork.' >&2
    exit 1
fi

# Replace the damaged alpha, preserving every RGB pixel. Inset the silhouette
# slightly into the clean chrome; supersample the mask for smooth edges.
magick "$source_image" -alpha off \
    \( -size 5016x5016 xc:black -fill white \
       -draw 'roundrectangle 184,216 4832,4800 256,256' \
       -filter box -resize 1254x1254 \) \
    -alpha off -compose CopyOpacity -composite -depth 8 RetroDLP-macOS.png

# Center the play button's vertical bounds (y=266..947) at y=606.5.
# Keep the horizontal center at x=626.5. A slightly tighter square excludes
# the outer chrome even with this upward shift of the source crop.
# Discard the source alpha rather than compositing its translucent body.
magick "$source_image" -alpha off -crop 1024x1024+115+95 +repage \
    -depth 8 PNG24:RetroDLP-iOS.png
