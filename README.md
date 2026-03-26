# SSH Connection Manager

Interactive TUI for managing SSH connections. Available in two versions: Node.js and Bash.

## Usage

```bash
# Node.js (recommended)
node ssh-manager.js

# Bash
./ssh-manager.sh
```

### Direct connect

```bash
./ssh-manager.js my-server
```

Connects immediately without opening the TUI.

## Keyboard shortcuts

| Key | Action |
|-----|--------|
| `↑` / `↓` | Navigate the list |
| `Enter` | Connect |
| `Ctrl+N` | Add new connection |
| `Ctrl+E` | Edit selected |
| `Ctrl+D` | Delete selected |
| `ESC` | Clear search / quit |
| `Ctrl+C` | Quit |
| Any character | Live search |

## Search

Start typing — the list filters in real time by name, hostname, and user. `ESC` clears the search.

## Config file

Connections are stored in `ssh-connections-config` using the standard `~/.ssh/config` format:

```
Host my-server
  HostName 192.168.1.10
  User pawel
  Port 22
  IdentityFile ~/.ssh/id_rsa
```

The file is fully compatible with plain SSH:

```bash
ssh -F ~/.ssh/ssh-connection-manager/ssh-connections-config my-server
```

## Requirements

| Version | Requirements |
|---------|--------------|
| `ssh-manager.js` | Node.js |
| `ssh-manager.sh` | Bash 3.2+, `tput`, `ssh` |
