# Accepted decisions

## 2026-10-04: Forever player identities

Steven approved implementing Forever support using the established first-name
and surname format. On Forever, keep canonical player keys as `First Surname`
without appending a realm, join both `UnitName` results with the native surname
separator, and use that same helper for login and raid identities. Keep the
existing realm-qualified identity handling on other clients.

Evidence: the local 1.60.1.70205 probe captured split first-name/surname results
for player, target, focus, and nameplates. Space-form exact targeting passed;
hyphen-form targeting failed. The supplied battleground scoreboard screenshot
shows space-separated full names, and that build's native scoreboard displays
`C_PvP.GetScoreInfo().name` unchanged. `RegionalUniqueNamesEnabled()` returned
true in the capture and is also used by native surname handling.

Source: Steven's approval in chat `01a108f3-673d-78a2-961c-ae381472357d`, after
the open-world tests and streamer scoreboard screenshots on 2026-10-04.
The observations above were made before this implementation. After deployment,
Steven reported that the result "seemed to be fine"; no battleground-specific
test was reported. Do not substitute `GetPlayerInfoByGUID` for active-PvP name
matching.

## 2026-10-04: Darkspear objective tracking deferred

Steven explicitly deferred Darkspear-specific objective support in the same
chat: "we dont need to add supprt for that yet". Keep the existing generic
15-player roster profile; do not add mechanic-specific objective handling as
part of the Forever compatibility deployment.
