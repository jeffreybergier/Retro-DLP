# Font Awesome screen scale

## Findings

- iOS passes the main screen's scale to Font Awesome and preserves the image's
  size in points. A 26-point Plus canvas is 52 × 52 pixels on a 2x screen.
  The earlier `scale:0` calls already did this through the installed
  `AIFontAwesome` implementation: it resolves zero to `UIScreen.mainScreen.scale`
  and constructs the result with `imageWithCGImage:scale:orientation:`.
- The Playlists navigation bar directly receives that image. There is no custom
  low-resolution drawing step in the app. Both the U+F067 and U+002B aliases map
  to the bundled font's same `plus` glyph.
- macOS already gets the owning window's `backingScaleFactor` through a runtime
  compatibility bridge; systems without that selector use 1x. Rendered control
  images are cached by glyph, style, point sizes, and scale. However, existing
  images were not refreshed when the window moved between display scales.
  The static Queue glyph and toolbar carets could retain their original scale.

## Changes

- Resolve iOS main-screen scale explicitly and include that scale in the status
  icon cache key. This makes the app's contract explicit; it does not establish
  that the reported Plus pixelation was caused by an incorrect render scale.
- Observe backing-property and screen changes on the actual macOS window.
  Refresh toolbar images and carets and request table cell images again using
  the window's new scale. Preserve the Tiger fallback and manual memory handling.

## Validation

- Universal iOS and macOS app builds; both native regression app builds.
  Both platform analyzers report zero warnings and zero errors.
- iOS coverage checks every icon helper's point size, bitmap dimensions, and
  `UIImage.scale`, the actual Plus navigation item, status cache reuse, and the
  dependency's automatic/1x/2x/3x behavior.
- The isolated icon test passes on x4-vm (Mac OS X 10.4): 1x/2x dimensions,
  transparency/color, cache reuse, the YouTube fallback, and owning-window
  notifications replacing deliberately stale Queue/caret images.
- After koolphone5 became reachable, the full native iOS suite passed, including
  every icon helper and the actual Plus navigation image. The phone renders its
  26-point Plus canvas at 52 × 52 pixels with `UIImage.scale == 2`; the captured
  library-screen image was also inspected. An incorrect screen scale was not
  reproduced as the cause of the reported Plus appearance.
- The Mac runner is 1x, so a real move between Retina/non-Retina displays remains
  a manual visual check. The notification-driven refresh regression passed.
