-- Run after mac_smoke.applescript against the same synthetic library only.
-- The smoke test cancels the queued fixture; no worker needs to be resumed.
on run argv
  set appProcess to "RetroDLP"
  if (count of argv) > 0 then set appProcess to item 1 of argv
  tell application "System Events"
    tell process appProcess
      set frontmost to true
      tell splitter group 1 of window 1 of process appProcess of application "System Events"
        if (count of rows of table 1 of scroll area 1) is not 2 then error "Not the isolated fixture library"
        if value of text field 1 of row 2 of table 1 of scroll area 1 does not start with "Offline test playlist" then error "Wrong fixture playlist"
        select row 1 of table 1 of scroll area 1
        delay 0.5
        if value of text field 1 of row 1 of table 1 of scroll area 2 is not "Portable video playback fixture" then error "Refusing to remove non-fixture media"
        select row 1 of table 1 of scroll area 2
        click menu button "Actions"
        click menu item 2 of menu 1 of menu button "Actions"
      end tell
      delay 0.5
      click button "Cancel" of sheet 1 of window 1 of process appProcess of application "System Events"
      delay 0.5
      tell splitter group 1 of window 1 of process appProcess of application "System Events"
        if (count of rows of table 1 of scroll area 2) is not 1 then error "Cancel removed the file"
        click menu button "Actions"
        click menu item 2 of menu 1 of menu button "Actions"
      end tell
      delay 0.5
      click button "Delete Download" of sheet 1 of window 1 of process appProcess of application "System Events"
      delay 0.5
      tell splitter group 1 of window 1 of process appProcess of application "System Events"
        if (count of rows of table 1 of scroll area 2) is not 0 then error "Download removal failed"
        select row 2 of table 1 of scroll area 1
        delay 0.5
        if (count of rows of table 1 of scroll area 2) is not 2 then error "Removing media removed membership"
        select row 1 of table 1 of scroll area 2
        click button "Show in Queue"
        delay 0.5
        if not (exists button "Download Video") then error "Removed job should offer Download Again"
        click menu button "Actions"
        click menu item 3 of menu 1 of menu button "Actions"
      end tell
      delay 0.5
      click button "Remove Playlist" of sheet 1 of window 1 of process appProcess of application "System Events"
      delay 0.5
      if (count of rows of table 1 of scroll area 1 of splitter group 1 of window 1 of process appProcess of application "System Events") is not 1 then error "Playlist removal failed"
      tell splitter group 1 of window 1 of process appProcess of application "System Events"
        if (count of rows of table 1 of scroll area 3) is not 0 then error "Queue should be empty after removal"
        click button "Resume Queue"
        delay 0.5
        if not (exists button "Pause Queue") then error "Queue toggle did not update"
        click button "Pause Queue"
      end tell
    end tell
  end tell
  return "PASS: confirmation cancellation, download removal, membership preservation, Download Again state, playlist removal, empty queue pause/resume"
end run
