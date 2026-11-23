# Car Driving World – how to get started

Everything Claude Code needs is already in this folder:

| File | What for |
|---|---|
| `CLAUDE.md` | The "brain" of the project: goal, rules, milestones. Claude Code reads it automatically on every start. |
| `PROMPTS.md` | All prompts to copy, milestone by milestone, plus emergency prompts. |
| `project.godot` | The Godot project. |

On your Windows PC you need Node.js, Git and Claude Code (e.g. via `winget install OpenJS.NodeJS.LTS Git.Git`).
Git is already set up in the project folder.
**Only Godot itself and the Godot connection for Claude Code are missing (step 3).**

---

## Step 1: Install Godot

Download the **standard version** (not the .NET version) for Windows:
https://godotengine.org/download/windows/

Unzip it, e.g. to `C:\Godot\`. It contains two programs:
`Godot_v4.7.2-stable_win64.exe` (the editor) and `Godot_v4.7.2-stable_win64_console.exe`
(the same version with text output, which Claude Code needs). Remember the path.

Alternatively in PowerShell: `winget install GodotEngine.GodotEngine`

You do not need an account for this.

## Step 2: Open the project once in Godot

1. Start Godot (double-click `Godot_v4.7.2-stable_win64.exe`). If Windows says
   "Windows protected your PC": **More info** → **Run anyway**.
2. In the project manager click **Import** and pick the file
   `project.godot` from this folder.
3. The project opens with an empty scene. That is correct.
   Close Godot again (or keep it open, does not matter).

## Step 3: Connect Claude Code to Godot

Open PowerShell and enter these two commands one after the other
(copy the second one in one piece, it is a long line):

```
cd C:\Godot-Projects\car-driving-world
```

```
claude mcp add godot --scope project -e GODOT_PATH=C:\Godot\Godot_v4.7.2-stable_win64_console.exe -- cmd /c npx -y @coding-solo/godot-mcp
```

That creates a `.mcp.json` file in the project. It lets Claude Code start Godot itself,
run the game and read error messages. You only need to do this once.

## Step 4: Start Claude Code

In the same PowerShell:

```
claude
```

On the first start Claude Code asks whether you trust the folder → **Yes**.
Then it asks whether it may use the MCP server "godot" from `.mcp.json` → **Yes**.

Quick check that the Godot connection works: type `/mcp`.
It should list **godot** as connected.

## Step 5: Get going

Open `PROMPTS.md`, copy the prompt for **milestone 0** and send it.
It also sets the permissions so Claude Code does not ask before every
Godot command. Then milestone 1, 2, 3 …

**Rules of thumb:**
- One fresh session per milestone (`/clear`).
- Only continue when the current milestone works.
- When it is about looks: take a screenshot (Windows + Shift + S) and simply
  paste it into the terminal (Ctrl + V).
- If Claude breaks something: there is a commit after every step,
  so you can always go back.

---

## Useful links

**Tools**
- Download Godot: https://godotengine.org/download/windows/
- Godot documentation: https://docs.godotengine.org/en/stable/
- Godot MCP server (the bridge between Claude Code and Godot): https://github.com/Coding-Solo/godot-mcp
- Claude Code documentation: https://code.claude.com/docs

**Free assets (all CC0, free to use)**
- Poly Haven – photorealistic textures, sky panoramas (HDRIs), models: https://polyhaven.com
- Kenney – cars, road pieces, trees, many models: https://kenney.nl/assets
- ambientCG – textures for asphalt, grass, rock, snow: https://ambientcg.com

---

## If something does not work

**`/mcp` does not show godot, or shows an error**
→ Does the `GODOT_PATH` in `.mcp.json` match your Godot file
(best the `_console.exe`)? If not, fix it and restart Claude Code.
→ Did you run the command from step 3 in the `car-driving-world` folder?
Check with `dir -Force` whether a `.mcp.json` is there.

**Claude Code asks for permission before every Godot command**
→ Choose "always allow" once, then it stops asking.

**The game stutters badly**
→ Use the "If it stutters" prompt from `PROMPTS.md`.
