-- Run only against prepare_native_fixture.py's isolated library.
-- Optional first argument: process name of a separately named review app.
-- No download, sync, retry, or destructive confirmation is approved.
on run argv
  set appProcess to "RetroDLP"
  if (count of argv) > 0 then set appProcess to item 1 of argv
  tell application "System Events"
    tell process appProcess
      set frontmost to true
      tell splitter group 1 of window "RetroDLP"
        if (count of scroll areas) is not 2 then error "Library must have only sidebar and video panes"
        if (count of rows of outline 1 of scroll area 1) is not 5 then error "Wrong fixture library"
        if value of text field 1 of row 4 of outline 1 of scroll area 1 does not start with "Offline test playlist" then error "Wrong fixture playlist"
        select row 4 of outline 1 of scroll area 1
      end tell
      click button "Queue" of group 4 of tool bar 1 of window "RetroDLP"
      delay 1
      if not (exists window "Download Queue") then error "Separate Queue window missing"
      tell window "Download Queue"
        if (count of rows of table 1 of scroll area 1) is not 3 then error "Queue lost fixture jobs"
        if not (exists button "Retry" of group 1 of tool bar 1) then error "Queue Retry control missing"
        if not (exists button "Delete" of group 4 of tool bar 1) then error "Queue Delete control missing"
        select row 1 of table 1 of scroll area 1
        click button "Stop" of group 2 of tool bar 1
      end tell
      delay 0.5
      if not (exists sheet 1 of window "Download Queue") then error "Stop confirmation must attach to Queue"
      if exists sheet 1 of window "RetroDLP" then error "Queue confirmation attached to Library"
      click button "Cancel" of sheet 1 of window "Download Queue"
      delay 0.5
      keystroke "w" using command down
      delay 0.5
      if exists window "Download Queue" then error "Queue did not close"
      if not (exists window "RetroDLP") then error "Closing Queue closed Library"
      click button "Queue" of group 4 of tool bar 1 of window "RetroDLP"
      delay 0.5
      if (count of rows of table 1 of scroll area 1 of window "Download Queue") is not 3 then error "Reopening Queue changed jobs"
      keystroke "w" using command down
      delay 0.5
      click menu bar item 2 of menu bar 1
      delay 0.5
      keystroke "d"
      key code 124
      delay 0.5
      keystroke "c"
      keystroke return
      delay 0.5
      if not (exists sheet 1 of window "RetroDLP") then error "Custom format sheet missing"
      set value of text field 1 of sheet 1 of window "RetroDLP" to "invalid-format"
      click button "Save" of sheet 1 of window "RetroDLP"
      delay 0.5
      if not (exists static text "Enter a valid format such as 18 or 136+140." of sheet 1 of window "RetroDLP") then error "Invalid format should stay in sheet"
      click button "Cancel" of sheet 1 of window "RetroDLP"
    end tell
  end tell
  return "PASS: two-pane library, separate Queue window and toolbar, queue-sheet cancellation, independent close/reopen, and application-menu quality validation; no network actions"
end run
