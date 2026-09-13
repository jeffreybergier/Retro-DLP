-- Destructive ONLY to the synthetic Desktop test library. Restore state.zip after.
tell application "System Events"
  tell process "RetroDLP"
    set frontmost to true
    tell splitter group 1 of window 1
      if (count of rows of table 1 of scroll area 1) is not 3 then error "Not the isolated fixture library"
      if value of text field 1 of row 3 of table 1 of scroll area 1 does not start with "Offline test playlist" then error "Wrong fixture playlist"
      select row 1 of table 1 of scroll area 1
      delay 0.5
      if value of text field 1 of row 1 of table 1 of scroll area 2 is not "Portable video playback fixture" then error "Refusing to remove non-fixture media"
      select row 1 of table 1 of scroll area 2
      click button "Remove Download"
    end tell
    delay 0.5
    click button "Cancel" of window 1
    delay 0.5
    tell splitter group 1 of window 1
      if (count of rows of table 1 of scroll area 2) is not 1 then error "Cancel removed the file"
      click button "Remove Download"
    end tell
    delay 0.5
    click button "Remove" of window 1
    delay 1
    tell splitter group 1 of window 1
      if (count of rows of table 1 of scroll area 2) is not 0 then error "Download removal failed"
      select row 3 of table 1 of scroll area 1
      delay 0.5
      if (count of rows of table 1 of scroll area 2) is not 2 then error "Removing media removed membership"
      click button "Remove Playlist"
    end tell
    delay 0.5
    click button "Remove" of window 1
    delay 1
    if (count of rows of table 1 of scroll area 1 of splitter group 1 of window 1) is not 2 then error "Playlist removal failed"
  end tell
end tell
return "PASS: Tiger removal confirmation, cancellation, file removal, membership preservation, and playlist removal"
