local Data = select(2, ...)

-- Instance IDs from BattlemasterListXMap (5.5.4), values are the per-team brackets.
Data.BattlegroundTeamSizes = {
  [30] = 40, -- Alterac Valley
  [489] = 10, -- Warsong Gulch
  [529] = 15, -- Arathi Basin
  [566] = 15, -- Eye of the Storm
  [607] = 15, -- Strand of the Ancients
  [628] = 40, -- Isle of Conquest
  [726] = 10, -- Twin Peaks
  [727] = 10, -- Silvershard Mines
  [761] = 10, -- The Battle for Gilneas
  [968] = 10, -- Rated Eye of the Storm
  [998] = 10, -- Temple of Kotmogu
  [1105] = 15, -- Deepwind Gorge
}
