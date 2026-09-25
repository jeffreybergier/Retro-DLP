# Audio language mux fixtures

These tiny files contain generated black video and silence. They let the offline
C tests mux real H.264/AAC inputs without requiring FFmpeg at test runtime.

Generated with:

```sh
ffmpeg -f lavfi -i color=c=black:s=32x32:r=10 -t 0.2 -an \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart language-video.mp4
ffmpeg -f lavfi -i anullsrc=r=44100:cl=stereo -t 0.2 -vn \
  -c:a aac -b:a 128k -movflags +faststart language-audio.m4a
```
