-- Arguments: isolated test process name, absolute synthetic cookie-file path.
-- Imports/removes only the test library's working copy; never discovers playlists.
on run argv
  if (count of argv) is not 2 then error "Supply test process and synthetic cookie path"
  set appProcess to item 1 of argv
  set cookiePath to item 2 of argv
  set cookieName to do shell script "/usr/bin/basename " & quoted form of cookiePath
  tell application "System Events"
    tell process appProcess
      set frontmost to true
      click button "Cookies" of group 3 of tool bar 1 of window 1 of process appProcess of application "System Events"
      delay 1
      keystroke "g" using {command down, shift down}
      delay 1
      set value of text field 1 of sheet 1 of window 1 of process appProcess of application "System Events" to cookiePath
      click button "Go" of sheet 1 of window 1 of process appProcess of application "System Events"
      delay 1
      keystroke cookieName
      delay 1
      click button "Open" of window 1 of process appProcess of application "System Events"
      delay 1
      if not (exists button "Cookies" of group 3 of tool bar 1 of window 1 of process appProcess of application "System Events") then error "Cookies toolbar button missing after import"
      tell splitter group 1 of window 1 of process appProcess of application "System Events"
        select row 2 of table 1 of scroll area 1
        select row 1 of table 1 of scroll area 2
      end tell
      if not (exists button "Cookies" of group 3 of tool bar 1 of window 1 of process appProcess of application "System Events") then error "Selection changed Cookies label"
      perform action "AXShowMenu" of button "Cookies" of group 3 of tool bar 1 of window 1 of process appProcess of application "System Events"
      delay 0.5
      key code 125
      key code 125
      keystroke return
      delay 0.5
      click button "Cancel" of sheet 1 of window 1 of process appProcess of application "System Events"
      delay 0.5
      if not (exists button "Cookies" of group 3 of tool bar 1 of window 1 of process appProcess of application "System Events") then error "Cookies toolbar button missing after cancellation"
      perform action "AXShowMenu" of button "Cookies" of group 3 of tool bar 1 of window 1 of process appProcess of application "System Events"
      delay 0.5
      key code 125
      key code 125
      keystroke return
      delay 0.5
      click button "Remove" of sheet 1 of window 1 of process appProcess of application "System Events"
      delay 0.5
      if not (exists button "Cookies" of group 3 of tool bar 1 of window 1 of process appProcess of application "System Events") then error "Cookies toolbar button missing after removal"
    end tell
  end tell
  return "PASS: cookie import, stable toolbar label across selection, confirmation cancellation, and removal; no account discovery"
end run
