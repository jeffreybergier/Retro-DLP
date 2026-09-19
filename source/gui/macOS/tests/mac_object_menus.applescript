-- Run only against an isolated prepare_native_fixture.py review app.
on run argv
  set appProcess to "RetroDLPToolbarReview"
  if (count of argv) > 0 then set appProcess to item 1 of argv
tell application "System Events"
  tell process appProcess
    set frontmost to true
    if exists menu bar item "Download" of menu bar 1 then error "Unexpected Download menu"
    if exists menu bar item "Play" of menu bar 1 then error "Unexpected Play menu"
    if exists menu bar item "Cookies" of menu bar 1 then error "Cookies must not be top-level"
    if exists menu bar item "Queue" of menu bar 1 then error "Queue must not be top-level"
    if not (exists menu bar item "View" of menu bar 1) then error "Missing View menu"
    set menuNames to name of every menu bar item of menu bar 1
    set objectMenus to {}
    repeat with menuName in menuNames
      if (contents of menuName) is in {"File", "Edit", "View", "Window", "Help"} then set end of objectMenus to contents of menuName
    end repeat
    if objectMenus is not {"File", "Edit", "View", "Window", "Help"} then error "Incorrect menu order"
    if (count of menuNames) is not 7 then error "Unexpected extra application menu"
    click menu bar item 2 of menu bar 1
    delay 0.5
    if not (exists menu item "Cookies" of menu 1 of menu bar item 2 of menu bar 1) then error "Cookies missing from application menu"
    key code 53
    click menu bar item "View" of menu bar 1
    delay 0.5
    click menu item "Hide Playlists" of menu 1 of menu bar item "View" of menu bar 1
    delay 1
    click menu bar item "View" of menu bar 1
    delay 0.5
    click menu item "Show Playlists" of menu 1 of menu bar item "View" of menu bar 1
    delay 1
    click menu bar item "View" of menu bar 1
    delay 0.5
    click menu item "Show Download Queue" of menu 1 of menu bar item "View" of menu bar 1
    delay 1
    if not (exists window "Download Queue") then error "Queue window did not open"
    keystroke "w" using command down
    delay 1
    click menu bar item "File" of menu bar 1
    delay 0.5
    click (first menu item whose name starts with "Add Playlist") of menu 1 of menu bar item "File" of menu bar 1
    delay 0.5
    if not (exists sheet 1 of window 1) then error "Menu bar Add did not open sheet"
    click button "Cancel" of sheet 1 of window 1
    delay 0.5
    click menu bar item "File" of menu bar 1
    delay 0.5
    if enabled of menu item "Play Playlist" of menu 1 of menu bar item "File" of menu bar 1 then error "No selection must disable video playback"
    key code 53
  end tell
end tell
return "PASS: application menu registration, menu order, nested Cookies, sidebar toggle and independent Queue window, Add sheet, disabled playback"
end run
