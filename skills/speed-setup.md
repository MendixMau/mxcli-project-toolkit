# Speed Setup: make the toolkit faster on this machine
**Applies to:** any mxcli project
**Purpose:** The steps Claude takes when a user says "update the toolkit, run doctor and check whether it can be faster on my machine" (Dutch: "werk de toolkit bij in dit project, draai doctor en controleer of het sneller kan op mijn machine"), "the toolkit is slow", or an exec/gate takes minutes. Bring the project's copies up to date, VALIDATE whether this machine is slower than it should be, and only if it is, name the one fix that works here, do it with the user and measure again.

## When to use
The user complains about speed, asks to update the toolkit and check whether it can be faster (English or Dutch, see Purpose), or asks for doctor to make it faster. Do not use it for a build that is slow because the MODEL is big: the bench says which it is.

## Steps (in order; the user is asked before every change, except the read-only ones)
0. Update first. Check that the toolkit clone was pulled (`git -C <toolkit> status -sb` shows it is not behind; if it is, ask before pulling). Then run `<toolkit>/bin/sync-project.sh <project>`. Report in plain words what sync changed, and every locally modified script it KEPT (it never overwrites those; say which, and that `--upgrade-bin <name>` replaces one after a backup, only if the user asks).
1. Run `bin/doctor.sh --bench .` from the project root. It changes no project file (only git's own stat cache, as any git status does) and takes about a minute. Read the table (step, this machine, reference, factor), the "Machine health" lines and the closing "Recommended fix" block.
2. VALIDATE first: is this machine slower than it should be? Use the verdict line and the Machine health lines. If the verdict says about as fast as the reference, Machine health is clean and the block says "None needed", say so in ONE line ("This machine is already fast: <verdict>") and STOP. Do not propose a fix for a fast machine. Otherwise say the result in ONE plain sentence, from the verdict line, for example: "This machine is 6x slower than the reference, mainly because every process start takes 100 ms instead of 2 ms." If Machine health warned, say that first, in words a non-developer knows. Users do not know what deno, mxbuild or a helper process is; never use those words to them. Wrong: "47 leftover deno helpers, run --cleanup?" Right: "Mendix build processes that were left running hold 3 GB of memory. Restarting your computer clears them; or I can stop just those now, if you say yes (`bin/doctor.sh --cleanup`)." For a project in a OneDrive/Dropbox/iCloud folder, the fix is moving the project to a local folder (the Recommended fix says how).
3. Only when step 2 found a problem: carry out the "Recommended fix" with the user. It names ONE option, the first that works here:
   - **Remove `Gate mode: full` from PROJECT.md** (the quick `mx check` per write is the default). Show the line, ask, remove it. Nothing else changes.
   - **Move the project out of a synced folder** (OneDrive, Dropbox, Google Drive, iCloud). Ask, then move or re-clone it to the local folder the block names, and reopen it there. This comes before WSL, a dev container or the cloud: a synced folder slows every option, so move first and bench again.
   - **Turn on git's file cache** (git status slow, process starts fine): the `git config` lines the block prints, in the project, after asking.
   - **Run the toolkit in WSL** (Windows, WSL already present). Guide: open the WSL shell, clone the project inside the WSL filesystem (not under /mnt/c), run `bin/doctor.sh` there. Ask before each step.
   - **Use a dev container** (docker or podman already runs). Guide through the project's container setup; ask before each step.
   - **Let Claude work in the cloud** (Claude Code on the web). The user pulls the result into Studio Pro with `git pull`. Nothing is installed locally.
4. Run `bin/doctor.sh --bench .` again, in the new place if the fix moved the work, and show before and after as two verdict lines plus the process-start figure.

## Never
- Never install anything without the user saying yes to that install.
- Never suggest antivirus exclusions or anything else that needs IT's permission. The fixes above need nobody's.
- Never claim an improvement the second bench does not show. If it shows none, say so and offer the next option in the order above.
