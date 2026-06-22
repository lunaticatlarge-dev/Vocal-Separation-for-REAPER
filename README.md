# Vocal Separation for REAPER

AI-powered vocal/stem separation using [Demucs](https://github.com/facebookresearch/demucs) inside REAPER.

Separate any audio item into individual stems — vocals, drums, bass, guitar, piano, and more — each on its own track.

## Requirements

- **macOS** (Apple Silicon)
- **Homebrew** — if not installed, run:
  ```
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ```
- **Python 3** (installed via Homebrew):
  ```
  brew install python@3.12
  ```
- **Demucs** (the AI separation engine):
  ```
  pip install demucs torch torchaudio
  ```
- **FFmpeg** (required by Demucs):
  ```
  brew install ffmpeg
  ```

Verify everything is installed:
```
python3 -c "import demucs; print('OK')"
```
If no errors, you're ready.

## Installation in REAPER

### Step 1 — Copy the script

Place `vocal_separation.lua` in REAPER's Scripts folder:
```
~/Library/Application Support/REAPER/Scripts/
```

You can open this folder from Finder: press `Cmd+Shift+G` and paste the path above.

### Step 2 — Load the script in REAPER

1. Open REAPER
2. Go to **Actions > Show Action List** (or press `?`)
3. Click the **ReaScript: Load** button (or **New Action > Load ReaScript**)
4. Navigate to `vocal_separation.lua` and select it
5. The action now appears in the list as **Script: vocal_separation.lua**

### Step 3 — (Optional) Assign a shortcut or toolbar button

In the Action List:
1. Find **Script: vocal_separation.lua**
2. Click **Add** in the Shortcuts section
3. Press a key combo (e.g. `Cmd+Shift+V`)
4. Click **OK**

Or drag the action onto a toolbar:
1. Right-click a toolbar → **Customize Toolbar**
2. Find the action in the list and drag it onto the toolbar

## Usage

### Running the script

1. **Select an audio item** in the arrange view (click on it)
2. **Run the script** — via shortcut, toolbar, or Actions list
3. A dialog asks for **Mode** and **Model**

### Mode options

| Number | Mode                | What it does                              |
|--------|---------------------|-------------------------------------------|
| 1      | All 4 stems         | Separates vocals, drums, bass, other      |
| 2      | All 6 stems         | Also extracts guitar and piano            |
| 3      | Vocals only         | Imports just the vocal stem               |
| 4      | Remove vocals       | Imports everything except vocals (karaoke)|
| 5      | Drums only          | Imports only the drum stem                |
| 6      | Bass only           | Imports only the bass stem                |
| 7      | Guitar only         | Imports only the guitar stem              |
| 8      | Piano only          | Imports only the piano stem               |

### Model options

| Number | Model            | Notes                                    |
|--------|------------------|------------------------------------------|
| 1      | htdemucs         | Default — good quality, fast             |
| 2      | htdemucs_ft      | Fine-tuned — slightly better, slower     |
| 3      | mdx_extra        | Alternative — varies by song             |
| 4      | htdemucs_6s      | 6-stem model — needed for guitar/piano   |

Modes 2, 7, and 8 auto-select `htdemucs_6s`.

### What happens

1. REAPER renders the selected audio to a temporary WAV file
2. Demucs processes it (console shows progress: `Rendering: 5%`, `10%`, etc.)
3. Demucs outputs separated stem files
4. REAPER creates a new track for each stem with the stem name
5. Temp files are cleaned up automatically

### Console output

Open **View > Show Console** (or press `Cmd+Shift+C`) to see progress and results.

## Troubleshooting

| Problem                          | Fix                                              |
|----------------------------------|--------------------------------------------------|
| "Demucs is not installed"        | Run `pip install demucs torch torchaudio`        |
| "Python3 not found"              | Install Homebrew Python: `brew install python@3.12` |
| Demucs runs but no stems appear  | Check the REAPER console for Demucs error output |
| "No stems matched filter"        | The selected model doesn't produce that stem (e.g., guitar requires htdemucs_6s) |
| First run is very slow           | Demucs downloads the model on first use — this is normal |

## License

MIT — use freely, modify, share.
