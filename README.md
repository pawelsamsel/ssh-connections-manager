# SSH Connection Manager

Interaktywny TUI do zarządzania połączeniami SSH. Dostępny w dwóch wersjach: Node.js i Bash.

## Uruchomienie

```bash
# Node.js (zalecane)
node ssh-manager.js

# Bash
./ssh-manager.sh
```

## Skróty klawiszowe

| Klawisz | Akcja |
|---------|-------|
| `↑` / `↓` | Nawigacja po liście |
| `Enter` | Połącz |
| `Ctrl+N` | Dodaj nowe połączenie |
| `Ctrl+E` | Edytuj zaznaczone |
| `Ctrl+D` | Usuń zaznaczone |
| `ESC` | Wyczyść wyszukiwanie / wyjdź |
| `Ctrl+C` | Wyjdź |
| Dowolny znak | Szukaj na żywo |

## Wyszukiwanie

Zacznij pisać — lista filtruje się na bieżąco po nazwie, hostname i użytkowniku. `ESC` czyści wyszukiwanie.

## Plik konfiguracyjny

Połączenia zapisywane są w `ssh-connections-config` w formacie standardowego `~/.ssh/config`:

```
Host my-server
  HostName 192.168.1.10
  User pawel
  Port 22
  IdentityFile ~/.ssh/id_rsa
```

Plik jest kompatybilny ze zwykłym SSH — można go używać bezpośrednio:

```bash
ssh -F ~/.ssh/ssh-connection-manager/ssh-connections-config my-server
```

## Wymagania

| Wersja | Wymagania |
|--------|-----------|
| `ssh-manager.js` | Node.js |
| `ssh-manager.sh` | Bash 3.2+, `tput`, `ssh` |
