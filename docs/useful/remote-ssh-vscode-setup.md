# VS Code Remote - SSH Setup for the UPM Server

Edit and run the repository on `b5g-bigtwin02.dit.upm.es` from VS Code on any computer. The code lives on the server and GitHub, so changing computers only means repeating the short setup in [§8](#8-move-to-a-new-computer).

---

## 1. What Lives Where

| Item | Location | Set up |
|---|---|---|
| Working copy of the repository | Server, `~/so-threat-fusion` | Once |
| Python environment (`.venv`) | Server, inside the repository | Once |
| GitHub access | Server, a deploy key for this repository | Once |
| VS Code remote extensions | Server, `~/.vscode-server` | Once |
| VS Code and Remote - SSH | Each computer | Per computer |
| UPM VPN | Each computer | Per computer |
| SSH key and `~/.ssh/config` | Each computer | Per computer |

---

## 2. Prepare the Computer

You need the **UPM VPN**, **VS Code** and an OpenSSH client. Windows 10/11 includes one: `ssh -V` should print a version.

Install the extension:

```powershell
code --install-extension ms-vscode-remote.remote-ssh
```

---

## 3. Create an SSH Key

Each computer uses its own key. Don't copy private keys between computers, and never commit them.

If the computer already has `~/.ssh/id_ed25519` (for example, the key you use for GitHub), reuse it and skip `ssh-keygen`. Answer **no** if `ssh-keygen` ever asks to overwrite a key, because that would destroy it.

Otherwise, create one:

```powershell
ssh-keygen -t ed25519 -C "marylin-<computer-name>"
```

Accept the default path and set a passphrase.

With the VPN on, add the public key to the server (PowerShell):

```powershell
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | ssh marylin@b5g-bigtwin02.dit.upm.es "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

On macOS or Linux:

```bash
ssh-copy-id marylin@b5g-bigtwin02.dit.upm.es
```

To reach the SO VM with the key as well, add it there too:

```powershell
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | ssh -J marylin@b5g-bigtwin02.dit.upm.es -p 2222 onionsec@127.0.0.1 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

---

## 4. Add the SSH Hosts

Add this to `~/.ssh/config` on the computer (`C:\Users\<you>\.ssh\config` on Windows):

```
Host bigtwin02
    HostName b5g-bigtwin02.dit.upm.es
    User marylin
    ServerAliveInterval 60

Host so-vm
    HostName 127.0.0.1
    Port 2222
    User onionsec
    ProxyJump bigtwin02
    ServerAliveInterval 60

Host so-web
    HostName 127.0.0.1
    Port 2222
    User onionsec
    ProxyJump bigtwin02
    DynamicForward 1080
    ServerAliveInterval 60
```

| Alias | Used for |
|---|---|
| `bigtwin02` | VS Code and development |
| `so-vm` | A shell on the SO VM |
| `so-web` | The SOCKS proxy for the web UI: run `ssh so-web`, then follow the [Firefox steps](../install/SO-install-[upm-server-virtualbox].md#54-access-the-soc-web-ui) |

Test the first two:

```powershell
ssh bigtwin02 hostname
ssh so-vm hostname
```

Connect VS Code to `bigtwin02`, not `so-vm`. This keeps the VS Code server and project dependencies off the Security Onion appliance.

---

## 5. Give the Server GitHub Access (once)

A deploy key belongs to the server and only opens this repository, so GitHub access keeps working when you change computers. Your personal GitHub key stays on your computer and is never needed on the server.

> ⚠️ **Security:** the server is shared and the key is stored on it, so anyone with root there could use it. Its reach is limited to this one repository. Don't put a personal access token in a git remote URL: it is saved in plain text in `.git/config`.

On the server (`ssh bigtwin02`):

```bash
ssh-keygen -t ed25519 -f ~/.ssh/github_so_threat_fusion -C "bigtwin02-so-threat-fusion"
cat >> ~/.ssh/config <<'EOF'

Host github.com
    IdentityFile ~/.ssh/github_so_threat_fusion
    IdentitiesOnly yes
EOF
chmod 600 ~/.ssh/config
cat ~/.ssh/github_so_threat_fusion.pub
```

On GitHub, open the repository's **Settings → Deploy keys → Add deploy key**, paste the public key and tick **Allow write access**.

Test it on the server:

```bash
ssh -T git@github.com
```

GitHub should greet you with the repository name and say it does not provide shell access.

---

## 6. Clone and Open the Repository (once)

On the old computer, commit and push whatever should reach the server. Check `git status` first, so that private notes stay out of the commit.

On the server:

```bash
git clone git@github.com:NyliStanwood/so-threat-fusion.git ~/so-threat-fusion
cd ~/so-threat-fusion
git config user.name "Marilyn Stanwood"
git config user.email "<your-github-email>"
python3 -m venv .venv
```

In VS Code:

1. Turn on the VPN.
2. Open the Command Palette (`Ctrl+Shift+P`) and run **Remote-SSH: Connect to Host**.
3. Choose `bigtwin02`, and **Linux** if asked for the platform.
4. Run **File → Open Folder** and choose `/home/marylin/so-threat-fusion` (confirm the path with `pwd` on the server).
5. Install the Python extension on the server: open the Extensions view and click **Install in SSH: bigtwin02** on `ms-python.python`.
6. Run **Python: Select Interpreter** and choose `.venv/bin/python`.

The bottom-left corner of VS Code should read **SSH: bigtwin02**. The integrated terminal now runs on the server.

---

## 7. Daily Use

1. Turn on the VPN.
2. In VS Code, use **File → Open Recent** and pick the `[SSH: bigtwin02]` entry.
3. Check the SO VM from the terminal: `VBoxManage list runningvms`.
4. Commit and push before you finish, so that GitHub has your work.

Files saved in VS Code are written directly to the server. Unsaved changes are held only while the connection lasts, so save often if the VPN is unstable.

---

## 8. Move to a New Computer

Before leaving the old computer, if you still have it:

- Push all commits from the server: `git status` should be clean and `git log origin/main..` empty.
- Copy anything that exists only locally, such as gitignored files (`.env`), the SO ISO, and the Claude Code memory in `~/.claude/projects/`.

On the new computer:

1. Install the UPM VPN and VS Code.
2. Install Remote - SSH ([§2](#2-prepare-the-computer)).
3. Create and register a new SSH key ([§3](#3-create-an-ssh-key)).
4. Add the SSH hosts ([§4](#4-add-the-ssh-hosts)).
5. Connect to `bigtwin02` and open the folder ([§6](#6-clone-and-open-the-repository-once), the VS Code steps).

The deploy key, clone and `.venv` are already on the server.

When the old computer is retired, remove its key from the server. Find the line with its `marylin-<computer-name>` comment:

```bash
nano ~/.ssh/authorized_keys
```

Do the same on the SO VM if you added the key there.

---

## 9. Troubleshooting

| Symptom | What to do |
|---|---|
| Connection times out | Check that the VPN is on, then run `ssh -v bigtwin02` |
| VS Code keeps asking for a passphrase | Windows, in an administrator PowerShell: `Set-Service ssh-agent -StartupType Automatic; Start-Service ssh-agent`. Then, in a normal one: `ssh-add` |
| `Bad owner or permissions` on the SSH config | The file must belong to your user only. On Linux or macOS: `chmod 600 ~/.ssh/config` |
| VS Code can't install or start its server | Run **Remote-SSH: Kill VS Code Server on Host**, then reconnect |
| `ssh -T git@github.com` times out on the server | Port 22 may be blocked. Add `HostName ssh.github.com` and `Port 443` under `Host github.com` in the server's `~/.ssh/config` |
| `python3 -m venv` reports that `ensurepip` is missing | The `python3-venv` package isn't installed and `sudo` is limited, so ask the tutor to install it |
| `ssh so-vm` ends with `Connection closed` | On the server: `bash ~/4.so-vbox-fix-forwards.sh` |
| `ssh so-web` reports that port 1080 is in use | Another proxy session is open. Close it |

---

## 10. Not Covered Here

This guide doesn't open access from the server to Elasticsearch on the SO VM (port 9200). The fusion engine will need that: a port-forward from the server, and permission in Security Onion's firewall.
