## Native and process-backed file dialogs exposed through Nest IO.

import std/[os, osproc, streams, strutils, tables]
import sdl3
import nest except Event, update, draw
import ../aseprite
import state

proc closeNestFallbackFilePicker(id: WidgetID) =
  if nestFallbackFilePickers.hasKey(id):
    nestFallbackFilePickers[id].close()
    nestFallbackFilePickers.del id

proc startNestFallbackFilePicker(id: WidgetID, defaultLocation: string): bool =
  if nestFallbackFilePickers.hasKey(id) and nestFallbackFilePickers[id].running:
    return true
  closeNestFallbackFilePicker(id)

  try:
    let zenity = findExe("zenity")
    if zenity.len > 0:
      echo "file picker fallback: zenity"
      var args = @["--file-selection"]
      if defaultLocation.len > 0:
        args.add "--filename=" & defaultLocation
      nestFallbackFilePickers[id] = startProcess(
        zenity, args = args, options = {poStdErrToStdOut}
      )
      requestFrameAfter(100)
      return true

    let kdialog = findExe("kdialog")
    if kdialog.len > 0:
      echo "file picker fallback: kdialog"
      var args = @["--getopenfilename"]
      if defaultLocation.len > 0:
        args.add defaultLocation
      nestFallbackFilePickers[id] = startProcess(
        kdialog, args = args, options = {poStdErrToStdOut}
      )
      requestFrameAfter(100)
      return true

    let yad = findExe("yad")
    if yad.len > 0:
      echo "file picker fallback: yad"
      var args = @["--file-selection"]
      if defaultLocation.len > 0:
        args.add "--filename=" & defaultLocation
      nestFallbackFilePickers[id] = startProcess(
        yad, args = args, options = {poStdErrToStdOut}
      )
      requestFrameAfter(100)
      return true

    nestFilePickerErrors[id] =
      "SDL file picker returned no selection and no fallback file picker was found"
  except CatchableError as error:
    nestFilePickerErrors[id] = error.msg
  if nestFilePickerErrors.getOrDefault(id).len > 0:
    echo "file picker error: ", nestFilePickerErrors[id]
  false

proc pollNestFallbackFilePickers*() =
  var finished: seq[WidgetID]
  var hasRunningPicker = false
  for id, process in nestFallbackFilePickers.mpairs:
    if process.running:
      hasRunningPicker = true
      continue
    let output = process.outputStream.readAll.strip
    let exitCode = process.peekExitCode()
    process.close()
    finished.add id
    if exitCode == 0 and output.len > 0:
      nestPickedFiles[id] = output.splitLines()[0]
      nestFilePickerErrors.del id
      echo "file picked: ", nestPickedFiles[id]
    elif exitCode != 0 and output.len > 0:
      nestFilePickerErrors[id] = output
      echo "file picker error: ", nestFilePickerErrors[id]
  for id in finished:
    nestFallbackFilePickers.del id
  if hasRunningPicker:
    requestFrameAfter(100)

proc nestOpenFile(id: WidgetID, defaultLocation: cstring): bool {.cdecl.} =
  try:
    nestFilePickerErrors.del id
    var completed = false
    var selected = false
    echo "file picker requested"
    dialogs.showOpenFileDialog(
      proc(result: dialogs.FileDialogResult) =
      completed = true
      selected = not result.canceled and result.paths.len > 0
      if selected:
        nestPickedFiles[id] = result.paths[0]
    ,
      defaultLocation = $defaultLocation,
      allowMany = false,
      window = nestWindow,
    )
    let dialogError = dialogs.dialogError()
    if dialogError.len > 0:
      nestFilePickerErrors[id] = dialogError
    if selected:
      return true
    if completed and nestFilePickerErrors.getOrDefault(id).len == 0:
      return startNestFallbackFilePicker(id, $defaultLocation)
    result = nestFilePickerErrors.getOrDefault(id).len == 0
    if not result:
      echo "file picker error: ", nestFilePickerErrors[id]
  except CatchableError as error:
    nestFilePickerErrors[id] = error.msg
    echo "file picker error: ", nestFilePickerErrors[id]
    result = false

proc nestFileValue(id: WidgetID): cstring {.cdecl.} =
  if nestPickedFiles.hasKey(id):
    nestPickedFiles[id].cstring
  else:
    cstring""

proc nestFileError(id: WidgetID): cstring {.cdecl.} =
  let dialogError = dialogs.dialogError()
  if dialogError.len > 0:
    nestFilePickerErrors[id] = dialogError
  if nestFilePickerErrors.hasKey(id):
    nestFilePickerErrors[id].cstring
  else:
    cstring""

proc nestClearFile(id: WidgetID) {.cdecl.} =
  nestPickedFiles.del id
  nestFilePickerErrors.del id
proc nestIO*(): IO =
  IO(
    files: FileIO(
      openFile: nestOpenFile,
      fileValue: nestFileValue,
      fileError: nestFileError,
      clearFile: nestClearFile,
    )
  )

