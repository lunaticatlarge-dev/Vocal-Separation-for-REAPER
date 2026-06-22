-- Vocal Separation using Demucs (AI-powered)
-- Select an audio item in REAPER, run this script.
-- Demucs separates the audio into stems (vocals, drums, bass, other, etc.)
-- and imports each stem onto its own track.
--
-- Requirements:
--   macOS (tested on Apple Silicon)
--   Homebrew Python 3:  /opt/homebrew/bin/python3
--   pip install demucs torch torchaudio
--   brew install ffmpeg
--
-- License: MIT
-- Copyright (c) 2026

function log(msg)
  reaper.ShowConsoleMsg(tostring(msg) .. "\n")
end

function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close(); return true end
  return false
end

function check_demucs()
  local handle = io.popen("KMP_DUPLICATE_LIB_OK=TRUE /opt/homebrew/bin/python3 -c \"import demucs; print('ok')\" 2>/dev/null")
  local result = handle:read("*a")
  handle:close()
  return result:match("ok") ~= nil
end

function get_temp_dir()
  return "/tmp/reaper_vocal_" .. math.random(100000, 999999)
end

function import_stem(stem_path, dest_track, position)
  local src = reaper.PCM_Source_CreateFromFile(stem_path)
  if not src then
    log("  Failed to create source: " .. stem_path)
    return false, nil
  end

  local item = reaper.AddMediaItemToTrack(dest_track)
  if not item then
    log("  Failed to add item to track")
    return false, nil
  end

  local take = reaper.AddTakeToMediaItem(item)
  if not take then
    log("  Failed to add take")
    return false, nil
  end

  reaper.SetMediaItemTake_Source(take, src)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", position)

  local len = reaper.GetMediaSourceLength(src, false)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", len)

  local name = stem_path:match("([^/]+)%.wav$") or stem_path:match("([^/]+)$")
  reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", name, true)

  return true, item
end

function show_options()
  log("")
  log("=== MODE ===")
  log("1 All 4 stems (voc, drums, bass, other)")
  log("2 All 6 stems (+ guitar, +piano)")
  log("3 Vocals only")
  log("4 Remove vocals (karaoke)")
  log("5 Drums only      6 Bass only")
  log("7 Guitar only     8 Piano only")
  log("=== MODEL ===")
  log("1 htdemucs      2 htdemucs_ft")
  log("3 mdx_extra     4 htdemucs_6s")
  log("")

  local retval, mode_str = reaper.GetUserInputs("Vocal Separation - Mode", 1, "Mode 1-8 (1=All, 3=Vocals, 4=Remove, 7=Guitar...)", "1")
  if not retval then return false end
  local mode = tonumber(mode_str) or 1
  if mode < 1 then mode = 1 elseif mode > 8 then mode = 8 end

  local model = 1
  if mode == 2 or mode == 7 or mode == 8 then
    model = 4
    log("Auto-selected htdemucs_6s for mode " .. mode)
  else
    local retval2, model_str = reaper.GetUserInputs("Vocal Separation - Model", 1, "Model 1-4 (1=htd, 4=htd_6s)", "1")
    if not retval2 then return false end
    model = tonumber(model_str) or 1
    if model < 1 then model = 1 elseif model > 4 then model = 4 end
  end

  return true, mode, model
end

function run()
  if not check_demucs() then
    log("==============================================")
    log("Demucs is not installed or Python not found.")
    log("")
    log("Install it in Terminal:")
    log("  pip install demucs torch torchaudio")
    log("  brew install ffmpeg")
    log("")
    log("Requirements:")
    log("  - macOS (Apple Silicon)")
    log("  - Homebrew Python 3 at /opt/homebrew/bin/python3")
    log("  - Demucs v4+ (pip install demucs)")
    log("  - FFmpeg (brew install ffmpeg)")
    log("==============================================")
    return
  end

  local ok, mode, model = show_options()
  if not ok then
    log("Cancelled.")
    return
  end
  log("Mode: " .. mode .. ", Model: " .. model)

  local sel_count = reaper.CountSelectedMediaItems(0)
  if sel_count == 0 then
    log("No items selected. Select an audio item first.")
    return
  end

  local item = reaper.GetSelectedMediaItem(0, 0)
  local take = reaper.GetActiveTake(item)
  if not take or take == 0 then
    log("Selected item has no audio take.")
    return
  end

  -- Use take name as source name
  local _, src_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  if not src_name or src_name == "" then src_name = "audio" end
  src_name = src_name:gsub("%.[^%.]+$", "")  -- strip extension
  local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

  local temp_dir = get_temp_dir()
  os.execute("mkdir -p \"" .. temp_dir .. "\"")

  local temp_wav = temp_dir .. "/" .. src_name .. "_full.wav"
  log("Rendering to " .. temp_wav)

  -- Read audio directly from original item (no glue needed)
  local src = take and reaper.GetMediaItemTake_Source(take)
  local sr = src and reaper.GetMediaSourceSampleRate(src) or 44100
  local length = item_len
  local nframes = math.floor(sr * length)
  if nframes <= 0 then
    log("Item has no audio data (length=0).")
    return
  end
  local nch = 2
  log(string.format("Audio: sr=%d, len=%.2fs, frames=%d, total_samples=%d", sr, length, nframes, nframes * nch))

  -- Process in chunks if the file is very large
  local chunk_frames = math.min(nframes, sr * 10)  -- max 10 seconds per chunk
  if chunk_frames <= 0 then chunk_frames = sr end

  os.execute("mkdir -p \"" .. temp_dir .. "\"")

  -- Write WAV with header first, then fill data in chunks
  local f = io.open(temp_wav, "wb")
  if not f then
    log("Failed to open temp file for writing.")
    return
  end

  local function w32(v)
    f:write(string.char(v & 0xFF, (v>>8) & 0xFF, (v>>16) & 0xFF, (v>>24) & 0xFF))
  end
  local function w16(v)
    f:write(string.char(v & 0xFF, (v>>8) & 0xFF))
  end

  local data_bytes = nframes * nch * 2
  -- Write placeholder header
  f:write("RIFF")
  w32(36 + data_bytes)
  f:write("WAVE")
  f:write("fmt ")
  w32(16)
  w16(1)
  w16(nch)
  w32(sr)
  w32(sr * nch * 2)
  w16(nch * 2)
  w16(16)
  f:write("data")
  w32(data_bytes)

  -- Write samples in chunks
  local acc = reaper.CreateTakeAudioAccessor(take)
  if not acc then
    log("Failed to create audio accessor.")
    f:close()
    os.remove(temp_wav)
    return
  end

  local written_frames = 0
  local last_pct = -1
  while written_frames < nframes do
    local this_chunk = math.min(chunk_frames, nframes - written_frames)
    local buf = reaper.new_array(this_chunk * nch)
    local got = reaper.GetAudioAccessorSamples(acc, sr, nch, written_frames / sr, this_chunk, buf)
    if got <= 0 then break end

    local nvals = this_chunk * nch
    for i = 1, nvals do
      local v = buf[i]
      if not v then v = 0 end
      v = math.max(-1, math.min(1, v))
      w16(math.floor(v * 32767 + 0.5))
    end
    written_frames = written_frames + this_chunk

    local pct = math.floor(written_frames / nframes * 100 / 5 + 0.5) * 5
    if pct ~= last_pct then
      last_pct = pct
      log(string.format("  Rendering: %d%%", pct))
      reaper.UpdateArrange()
    end
  end

  reaper.DestroyAudioAccessor(acc)
  f:close()

  log("  Rendering: 100%")

  if not file_exists(temp_wav) then
    log("Failed to write WAV file.")
    return
  end

  log("Running Demucs (may take a while for long files)...")

  -- Run Demucs with selected model and mode
  local model_names = {"htdemucs", "htdemucs_ft", "mdx_extra", "htdemucs_6s"}
  local model_name = model_names[model] or "htdemucs"
  local two_stems = ""
  if mode == 3 or mode == 4 then
    two_stems = " --two-stems vocals"
  end

  local output_dir = temp_dir .. "/separated"
  local cmd = string.format(
    "KMP_DUPLICATE_LIB_OK=TRUE /opt/homebrew/bin/python3 -m demucs -n %s%s -o \"%s\" \"%s\" 2>&1",
    model_name, two_stems, output_dir, temp_wav
  )

  local handle = io.popen(cmd)
  local result = handle:read("*a")
  handle:close()
  log(result)

  -- Check Demucs output for errors
  if result:match("[Ee]rror") or result:match("Traceback") or result:match("failed") then
    log("Demucs reported an error. Check the output above.")
    os.execute("rm -rf \"" .. temp_dir .. "\"")
    return
  end

  -- Find separated stems (Demucs names output dir after model name, then input filename)
  local stem_base = src_name .. "_full"
  local stem_dir = output_dir .. "/" .. model_name .. "/" .. stem_base

  if not file_exists(stem_dir) then
    log("Could not find separated stems in: " .. output_dir)
    return
  end

  -- List stem files (handle spaces in paths)
  local stems = {}
  local p = io.popen("ls -1 \"" .. stem_dir .. "\"/*.wav 2>/dev/null")
  for line in p:read("*a"):gmatch("([^\n]+)") do
    local f = line:match("^%s*(.-)%s*$")
    if f and f ~= "" and file_exists(f) then
      table.insert(stems, f)
    end
  end
  p:close()

  if #stems == 0 then
    log("No WAV stems found in: " .. stem_dir)
    return
  end

  -- Filter stems based on selected mode
  local filter_key = ""
  if mode == 3 then filter_key = "vocals"
  elseif mode == 4 then filter_key = "no_vocals"
  elseif mode == 5 then filter_key = "drums"
  elseif mode == 6 then filter_key = "bass"
  elseif mode == 7 then filter_key = "guitar"
  elseif mode == 8 then filter_key = "piano"
  end

  if filter_key ~= "" then
    local filtered = {}
    for _, s in ipairs(stems) do
      if s:match(filter_key) then
        table.insert(filtered, s)
      end
    end
    if #filtered == 0 then
      log("No stems matched filter: " .. filter_key)
      return
    end
    stems = filtered
    log("Filtered to stems matching: " .. filter_key)
  end

  -- Create a track for each stem
  local function add_track(name)
    local idx = reaper.GetNumTracks()
    reaper.InsertTrackAtIndex(idx, true)
    local t = reaper.GetTrack(0, idx)
    if t and name then
      reaper.GetSetMediaTrackInfo_String(t, "P_NAME", name, true)
    end
    return t
  end

  local imported = 0
  local first_track = nil
  for _, stem_path in ipairs(stems) do
    local stem_name = stem_path:match("([^/]+)%.wav$") or stem_path:match("([^/]+)$")
    local stem_track = add_track(stem_name)
    if not stem_track then break end

    local ok, item = import_stem(stem_path, stem_track, item_pos)
    if ok then
      imported = imported + 1
      if not first_track then first_track = stem_track end
      reaper.SetMediaItemSelected(item, true)
    end
  end

  if first_track then
    reaper.SetOnlyTrackSelected(first_track)
  end
  reaper.Main_OnCommand(40913, 0)
  reaper.SetEditCurPos(item_pos, false, false)
  reaper.Main_OnCommand(40033, 0)

  reaper.UpdateArrange()
  reaper.TrackList_AdjustWindows(false)

  log(string.format("Imported %d/%d stems on separate tracks", imported, #stems))

  -- Clean up temp files
  os.execute("rm -rf \"" .. temp_dir .. "\"")

  log("Done!")
end

run()
