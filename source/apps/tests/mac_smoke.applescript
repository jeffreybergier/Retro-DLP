-- Run only against the isolated library made by prepare_native_fixture.py.
-- No network operation is started: the Add test uses an invalid local input.
tell application "System Events"
  tell process "RetroDLP"
    set frontmost to true
    key code 53
    tell splitter group 1 of window 1
      if (count of rows of table 1 of scroll area 1) is less than 3 then error "Missing fixture playlist"
      select row 3 of table 1 of scroll area 1
      delay 0.5
      if (count of rows of table 1 of scroll area 2) is not 2 then error "Missing playlist entries"
      click pop up button 1
      click menu item 2 of menu 1 of pop up button 1
      delay 0.5
      if value of text field 2 is not "136+140" then error "Quality selection failed"
      click pop up button 1
      click menu item 1 of menu 1 of pop up button 1
      delay 0.5
      click button "Resume Queue"
      delay 1
      click button "Pause Queue"
      select row 1 of table 1 of scroll area 1
      delay 0.5
      if (count of rows of table 1 of scroll area 2) is not 1 then error "Missing completed download"
      select row 1 of table 1 of scroll area 2
      select row 3 of table 1 of scroll area 1
      delay 0.5
      set value of text field 1 to "not-a-playlist"
      click button "Add Playlist"
      delay 2
      if (count of rows of table 1 of scroll area 1) is not 3 then error "Invalid input changed library"
      set value of text field 1 to ""
      click button "Open in VLC"
      delay 2
    end tell
  end tell
end tell
return "PASS: Tiger playlist browsing, quality selection, queue controls, invalid input, and VLC handoff"
