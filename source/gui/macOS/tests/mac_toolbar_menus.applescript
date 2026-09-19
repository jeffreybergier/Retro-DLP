-- Run against the paused offline test bundle with RDToolbarPreview=1.
-- Exercises main clicks on menu-only buttons without approving any work.
on run argv
  set appProcess to "RetroDLPToolbarTest"
  if (count of argv) > 0 then set appProcess to item 1 of argv
  tell application "System Events"
    repeat 30 times
      if exists window "RetroDLP" of process appProcess then exit repeat
      delay 1
    end repeat
    tell process appProcess
      set frontmost to true
      tell tool bar 1 of window "RetroDLP"
        if not (exists button "Library" of group 1) then error "Library must be first"
        if not (exists button "Download" of group 2) then error "Download must be second"
        if not (exists button "Play" of group 3) then error "Play must be third"
        if not (exists button "Remove" of group 4) then error "Remove must be fourth"
        if not (exists button "Cookies" of group 5) then error "Cookies must be fifth"
        if not (exists button "Queue" of group 6) then error "Queue must be sixth"
        click button "Library" of group 1
      end tell
      delay 0.5
      if exists sheet 1 of window "RetroDLP" then error "Library click must open a menu, not a sheet"
      keystroke "Add Video"
      keystroke return
      delay 0.5
      if not (exists sheet 1 of window "RetroDLP") then error "Library menu did not dispatch Add Video"
      click button "Cancel" of sheet 1 of window "RetroDLP"
      delay 0.5
      click button "Cookies" of group 5 of tool bar 1 of window "RetroDLP"
      delay 0.5
      if exists sheet 1 of window "RetroDLP" then error "Cookies click must open a menu, not a sheet"
      key code 53
      delay 0.5
      tell splitter group 1 of window "RetroDLP"
        select row 4 of outline 1 of scroll area 1
        select row 1 of table 1 of scroll area 2
      end tell
      delay 0.5
      click button "Remove" of group 4 of tool bar 1 of window "RetroDLP"
      delay 0.5
      if not (exists sheet 1 of window "RetroDLP") then error "Remove must confirm the selected download"
      if not (exists button "Delete Download" of sheet 1 of window "RetroDLP") then error "Wrong removal action"
      click button "Cancel" of sheet 1 of window "RetroDLP"
    end tell
  end tell
  return "PASS: six toolbar buttons, Library and Cookies primary menus, Add Video dispatch, and separate Remove confirmation; no work approved"
end run
