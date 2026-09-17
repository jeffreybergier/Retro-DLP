-- Run only against prepare_native_fixture.py's isolated library.
-- Optional first argument: process name of a separately named test app.
-- No sync, discovery, download, retry, or resume action is invoked.
on run argv
  set appProcess to "RetroDLP"
  if (count of argv) > 0 then set appProcess to item 1 of argv
  tell application "System Events"
    tell process appProcess
      set frontmost to true
      key code 53
      tell splitter group 1 of window 1 of process appProcess of application "System Events"
        if (count of rows of outline 1 of scroll area 1) is not 5 then error "Wrong fixture library"
        if value of text field 1 of row 4 of outline 1 of scroll area 1 does not start with "Offline test playlist" then error "Wrong fixture playlist"
        select row 4 of outline 1 of scroll area 1
        delay 0.5
        if (count of rows of table 1 of scroll area 2) is not 2 then error "Missing playlist entries"
        select row 1 of table 1 of scroll area 2
        delay 1
        if not (exists button "Play" of group 2 of tool bar 1 of window 1 of process appProcess of application "System Events") then error "Play toolbar item missing"
        if exists pop up button 1 then error "Inline quality control should be removed"
        select row 2 of table 1 of scroll area 2
        click button "Show in Queue"
        delay 0.5
        if not (exists (first button whose name starts with "Cancel Download")) then error "Queued job should allow cancellation"
        if exists menu button "Download Actions" then error "Old inspector menu should be removed"
        select row 2 of table 1 of scroll area 3
        delay 1
        if not (enabled of button "Download Video") then error "Failed job should allow retry"
        set selectedQueueText to value of text field 1 of row 2 of table 1 of scroll area 3
        select row 2 of outline 1 of scroll area 1
        delay 0.5
        if value of text field 1 of (first row of table 1 of scroll area 3 whose selected is true) is not selectedQueueText then error "Sidebar changed queue selection"
        select row 4 of outline 1 of scroll area 1
        delay 0.5
        select row 2 of table 1 of scroll area 2
      end tell
      -- Tiger context menus are navigated by keyboard; they are not exposed
      -- as child AX menus. Only choose Custom, never a preset download.
      perform action "AXShowMenu" of button 1 of group 1 of tool bar 1 of window 1 of process appProcess of application "System Events"
      delay 0.5
      keystroke "d"
      key code 124
      delay 0.5
      keystroke "c"
      keystroke return
      delay 0.5
      if not (exists sheet 1 of window 1 of process appProcess of application "System Events") then error "Custom format sheet missing"
      set value of text field 1 of sheet 1 of window 1 of process appProcess of application "System Events" to "invalid-format"
      click button "Save" of sheet 1 of window 1 of process appProcess of application "System Events"
      delay 0.5
      if not (exists static text "Enter a valid format such as 18 or 136+140." of sheet 1 of window 1 of process appProcess of application "System Events") then error "Invalid format should stay in sheet"
      click button "Cancel" of sheet 1 of window 1 of process appProcess of application "System Events"
      delay 0.5
      tell splitter group 1 of window 1 of process appProcess of application "System Events"
        if (count of rows of table 1 of scroll area 3) is not 3 then error "Cancelled custom sheet changed jobs"
        if value of text field 2 of row 2 of table 1 of scroll area 2 is not "18" then error "Cancelled sheet changed format"
        select row 1 of table 1 of scroll area 3
        click (first button whose name starts with "Cancel Download")
      end tell
      delay 0.5
      click button "Cancel Download" of sheet 1 of window 1 of process appProcess of application "System Events"
      delay 0.5
      tell splitter group 1 of window 1 of process appProcess of application "System Events"
        if not (exists button "Download Video") then error "Cancelled job should allow retry"
        if not (exists button "Resume Queue") then error "Queue should remain paused"
      end tell
      click button 1 of group 4 of tool bar 1 of window 1 of process appProcess of application "System Events"
      delay 0.5
      if exists scroll area 3 of splitter group 1 of window 1 of process appProcess of application "System Events" then error "Queue toggle did not collapse inspector"
      click button 1 of group 4 of tool bar 1 of window 1 of process appProcess of application "System Events"
      delay 0.5
      if not (exists scroll area 3 of splitter group 1 of window 1 of process appProcess of application "System Events") then error "Queue toggle did not reveal inspector"
      select row 2 of outline 1 of scroll area 1 of splitter group 1 of window 1 of process appProcess of application "System Events"
      delay 0.5
      click button 1 of group 1 of tool bar 1 of window 1 of process appProcess of application "System Events"
      delay 0.5
      click button "Cancel" of sheet 1 of window 1 of process appProcess of application "System Events"
    end tell
  end tell
  return "PASS: native toolbar, Custom sheet validation/cancellation, independent queue selection, cancel/retry state, Queue toggle, and Add sheet cancellation; no network actions"
end run
