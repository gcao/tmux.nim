import strutils, strformat, re, osproc

type
  Tmux* = ref object
    windowsCache: seq[Window]

  Window* = ref object
    index*: int
    name*: string
    active*: bool
    last*: bool
    panesCache: seq[Pane]

  Pane* = ref object
    parent*: Window
    index*: int
    active*: bool
    buffer*: seq[string]

  HistoryItem* = ref object
    dir*: string
    cmd*: string

proc loadBuffer*(self: Pane)

let TmuxInstance = Tmux()

#1: Z (3 panes) [204x67] [layout cc9f,204x67,0,0,2] @1
#2: Servers   (4 panes) [204x67] [layout 3710,204x67,0,0{129x67,0,0[129x32,0,0,4,129x34,0,33,5],74x67,130,0[74x32,130,0,6,74x34,130,33,7]}] @2
#3: AdminV2 - (3 panes) [204x67] [layout 0ab1,204x67,0,0{129x67,0,0,8,74x67,130,0[74x32,130,0,9,74x34,130,33,10]}] @3
#4: HDAP   (3 panes) [204x67] [layout 8deb,204x67,0,0{129x67,0,0,11,74x67,130,0[74x34,130,0,12,74x32,130,35,13]}] @4
#5: Tmux Workflow * (3 panes) [204x67] [layout 0e01,204x67,0,0{129x67,0,0,14,74x67,130,0[74x34,130,0,15,74x32,130,35,16]}] @5 (active)
#6: SSU Redesign Z (3 panes) [204x67] [layout 6686,204x67,0,0,17] @6
#7: Misc Z (3 panes) [204x67] [layout e681,204x67,0,0,22] @7
#8:   (3 panes) [204x67] [layout ce00,204x67,0,0{129x67,0,0,23,74x67,130,0[74x34,130,0,24,74x32,130,35,25]}] @8
#9: Agent   (3 panes) [204x67] [layout 4e1a,204x67,0,0{129x67,0,0,26,74x67,130,0[74x34,130,0,27,74x32,130,35,28]}] @9
proc lineToWindow(line: string): Window =
  result = Window()
  discard line =~ re"^(\d+):\s+([^(]+)?\s+\("
  result.index = matches[0].parseInt()
  result.name = matches[1].strip()
  result.active = result.name =~ re"\*Z?$"
  result.last = result.name =~ re"-Z?$"
  result.name = result.name.replace(re"Z$").replace(re"[\-\*]$").strip()

#0: [129x67] [history 6889/20000, 1466530 bytes] %1
#1: [204x67] [history 138/20000, 80566 bytes] %2 (active)
#2: [74x34] [history 595/20000, 499310 bytes] %3
proc lineToPane(parent: Window, line: string): Pane =
  # @parent = parent
  # representation =~ /^(\d)+:[^\(]*(\(active\))?\s*$/
  # @index  = $1.to_i + 1
  # @active = !!$2
  result = Pane(parent: parent)
  discard line =~ re"^(\d)+:[^\(]*(\(active\))?\s*$"
  result.index = matches[0].parseInt()
  result.active = matches[1].len > 0
  result.loadBuffer()

proc windows*(): seq[Window] =
  if TmuxInstance.windowsCache.len == 0:
    for line in execProcess("tmux list-windows").split("\n"):
      if line.len == 0:
        continue
      TmuxInstance.windowsCache.add(lineToWindow(line))

  TmuxInstance.windowsCache

proc rename*(self: Window, newName: string) =
  echo execProcess(fmt"tmux rename-window -t {self.index} {$newName}")

proc panes*(self: Window): seq[Pane] =
  if self.panesCache.len == 0:
    for line in execProcess(fmt"tmux list-panes -t {self.index}").split("\n"):
      if line.len == 0:
        continue
      self.panesCache.add(self.lineToPane(line))

  self.panesCache

# tmux capture-pane -t:{parent.index}.{self.index - 1} -p -J -S -500
proc loadBuffer*(self: Pane) =
  self.buffer = execProcess(fmt"tmux capture-pane -t:{self.parent.index}.{self.index} -p -J -S -500").strip().split("\n")

proc dir*(self: Pane): string =
  # last_line = buffer.lines.last
  # if last_line.encode('utf-8', 'utf-8') =~ / ([^\uE0B0]*[\/~][^\uE0B0]*) \uE0B0/
  #   @dir = $1
  # end
  var last = self.buffer[^1]
  if last =~ re"^([^]+) " and not last.contains(":"):
    matches[0].strip()
  else:
    ""

proc process*(self: Pane): string =
  var last = self.buffer[^1]
  if last.contains(":"):
    return "Vim"
  elif self.buffer.len >= 2:
    var secondLast = self.buffer[^2]
    if secondLast.contains(":"):
      return "Vim"

  if not last.contains(""):
    return "Longrunning process"

proc history*(self: Pane): seq[HistoryItem] =
  for line in self.buffer:
    if line =~ re"^([^]+) (.+) (.*)$":
      var dir = matches[0]
      var cmd = matches[2].strip
      if result.len == 0 or cmd.len > 0:
        result.add(HistoryItem(dir: dir, cmd: cmd))
    elif line =~ re"^([^]+)  ([^]*)$":
      var dir = matches[0]
      var cmd = matches[1].strip
      if result.len == 0 or cmd.len > 0:
        result.add(HistoryItem(dir: dir, cmd: cmd))

proc `$`(self: Pane): string =
  result = $(self.index+1) & "."
  if self.dir.len > 0:
    result &= " " & self.dir
  if self.process.len > 0:
    result &= " " & self.process
  else:
    result &= " $"

when isMainModule:
  echo "Tmux"
  for window in windows():
    echo fmt"  {window.index}. {window.name}"
    for pane in window.panes:
      echo fmt"    {pane}"
      if pane.process != "Vim":
        for item in pane.history:
          echo fmt"       {item.dir.strip} $ {item.cmd.strip}"
