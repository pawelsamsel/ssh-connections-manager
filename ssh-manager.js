#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { execSync, spawn } = require('child_process');

const CONFIG_FILE = path.join(__dirname, 'ssh-connections-config');

// ── Parser ────────────────────────────────────────────────────────────────────

function parseConfig(text) {
  const connections = [];
  let current = null;

  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;

    if (line.toLowerCase().startsWith('host ')) {
      if (current) connections.push(current);
      current = { Host: line.slice(5).trim() };
    } else if (current) {
      const spaceIdx = line.indexOf(' ');
      if (spaceIdx !== -1) {
        const key = line.slice(0, spaceIdx).trim();
        const val = line.slice(spaceIdx + 1).trim();
        current[key] = val;
      }
    }
  }
  if (current) connections.push(current);
  return connections;
}

function serializeConfig(connections) {
  return connections.map(c => {
    const { Host, ...rest } = c;
    const lines = [`Host ${Host}`];
    for (const [k, v] of Object.entries(rest)) {
      lines.push(`  ${k} ${v}`);
    }
    return lines.join('\n');
  }).join('\n\n') + '\n';
}

function loadConnections() {
  if (!fs.existsSync(CONFIG_FILE)) return [];
  return parseConfig(fs.readFileSync(CONFIG_FILE, 'utf8'));
}

function saveConnections(connections) {
  fs.writeFileSync(CONFIG_FILE, serializeConfig(connections), 'utf8');
}

// ── Terminal helpers ──────────────────────────────────────────────────────────

const ESC = '\x1b';
const RESET  = `${ESC}[0m`;
const BOLD   = `${ESC}[1m`;
const DIM    = `${ESC}[2m`;
const CYAN   = `${ESC}[36m`;
const GREEN  = `${ESC}[32m`;
const YELLOW = `${ESC}[33m`;
const RED    = `${ESC}[31m`;
const BG_BLUE   = `${ESC}[44m`;
const BG_CYAN   = `${ESC}[46m`;
const FG_WHITE  = `${ESC}[97m`;
const FG_BLACK  = `${ESC}[30m`;

const W = process.stdout.columns || 80;

function clearScreen()  { process.stdout.write(`${ESC}[2J${ESC}[H`); }
function hideCursor()   { process.stdout.write(`${ESC}[?25l`); }
function showCursor()   { process.stdout.write(`${ESC}[?25h`); }
function moveTo(r, c)   { process.stdout.write(`${ESC}[${r};${c}H`); }
function clearLine()    { process.stdout.write(`${ESC}[2K`); }

let _buf = null;
function beginFrame() { _buf = []; }
function endFrame()   { process.stdout.write(_buf.join('')); _buf = null; }
function print(s)     { if (_buf !== null) _buf.push(s); else process.stdout.write(s); }

function centerPad(text, width, fillChar = ' ') {
  const plain = text.replace(/\x1b\[[0-9;]*m/g, '');
  const pad = Math.max(0, width - plain.length);
  const left = Math.floor(pad / 2);
  const right = pad - left;
  return fillChar.repeat(left) + text + fillChar.repeat(right);
}

function truncate(s, max) {
  return s.length > max ? s.slice(0, max - 1) + '…' : s;
}

// ── Main TUI ──────────────────────────────────────────────────────────────────

class SSHManager {
  constructor() {
    this.connections = loadConnections();
    this.cursor = 0;
    this.offset = 0;
    this.message = '';
    this.messageColor = GREEN;
    this.searchQuery = '';
    this.pendingDelete = false;
  }

  get visibleRows() {
    return Math.max(3, (process.stdout.rows || 24) - 12);
  }

  get filteredConnections() {
    if (!this.searchQuery) return this.connections;
    const q = this.searchQuery.toLowerCase();
    return this.connections.filter(c =>
      (c.Host || '').toLowerCase().includes(q) ||
      (c.HostName || '').toLowerCase().includes(q) ||
      (c.User || '').toLowerCase().includes(q)
    );
  }

  render() {
    beginFrame();
    // Move to top-left without clearing — avoids flicker
    print(`${ESC}[H`);
    const w = process.stdout.columns || 80;

    // Header
    print(BG_CYAN + FG_BLACK + BOLD);
    print(centerPad('  SSH Connection Manager', w));
    print(RESET + '\n');
    print(DIM + centerPad(`Config: ${CONFIG_FILE}`, w) + RESET + '\n');
    print('\n');

    // Search bar
    if (this.searchQuery) {
      print(`  ${BOLD}Search:${RESET} ${CYAN}${this.searchQuery}${RESET}${DIM}▌${RESET}  ${DIM}(ESC to clear)${RESET}\n\n`);
    } else {
      print(`  ${DIM}Start typing to search…${RESET}\n\n`);
    }

    const filtered = this.filteredConnections;

    if (this.connections.length === 0) {
      print(DIM + centerPad('No connections yet. Press Ctrl+N to add one.', w) + RESET + '\n');
    } else if (filtered.length === 0) {
      print(DIM + centerPad(`No matches for "${this.searchQuery}"`, w) + RESET + '\n');
    } else {
      const maxVisible = this.visibleRows;
      const end = Math.min(this.offset + maxVisible, filtered.length);

      // Column headers
      const nameW = Math.floor(w * 0.30);
      const hostW = Math.floor(w * 0.30);
      const userW = Math.floor(w * 0.15);
      const portW = 8;

      print(BOLD + CYAN);
      print(`  ${'NAME'.padEnd(nameW)} ${'HOSTNAME'.padEnd(hostW)} ${'USER'.padEnd(userW)} ${'PORT'.padEnd(portW)}\n`);
      print(RESET + DIM + '─'.repeat(w) + RESET + '\n');

      for (let i = this.offset; i < end; i++) {
        const c = filtered[i];
        const selected = i === this.cursor;
        const name = truncate(c.Host || '', nameW);
        const host = truncate(c.HostName || '', hostW);
        const user = truncate(c.User || '', userW);
        const port = c.Port || '22';

        if (selected) {
          print(BG_BLUE + FG_WHITE + BOLD);
          print(`▶ ${name.padEnd(nameW)} ${host.padEnd(hostW)} ${user.padEnd(userW)} ${port.padEnd(portW)}`);
          print(RESET + '\n');
        } else {
          print(`  ${name.padEnd(nameW)} ${DIM}${host.padEnd(hostW)}${RESET} ${GREEN}${user.padEnd(userW)}${RESET} ${YELLOW}${port.padEnd(portW)}${RESET}\n`);
        }
      }

      // Scroll indicator
      if (filtered.length > maxVisible) {
        const scrollPct = Math.round((this.offset / (filtered.length - maxVisible)) * 100);
        print(DIM + `\n  Showing ${this.offset + 1}–${end} of ${filtered.length}  (${scrollPct}% scrolled)` + RESET + '\n');
      }
    }

    // Separator
    print('\n' + DIM + '─'.repeat(w) + RESET + '\n');

    // Help bar
    const keys = [
      ['↑↓', 'navigate'],
      ['Enter', 'connect'],
      ['^N', 'new'],
      ['^E', 'edit'],
      ['^D', 'delete'],
      ['ESC', 'search/quit'],
      ['^C', 'quit'],
    ];
    print(keys.map(([k, desc]) => `${BOLD}${CYAN}${k}${RESET} ${DIM}${desc}${RESET}`).join('  ') + '\n');

    // Status message
    if (this.message) {
      print('\n' + this.messageColor + this.message + RESET + '\n');
    }

    // Clear anything below the current frame
    print(`${ESC}[J`);
    endFrame();
  }

  askField(prompt, defaultVal = '') {
    return new Promise((resolve, reject) => {
      const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
      let done = false;

      const finish = (action, value) => {
        if (done) return;
        done = true;
        process.stdin.removeListener('keypress', onKeypress);
        if (action === 'resolve') resolve(value);
        else reject(new Error('cancelled'));
      };

      const onKeypress = (ch, key) => {
        if (key && key.name === 'escape') {
          rl.close();
          finish('reject');
        }
      };

      readline.emitKeypressEvents(process.stdin);
      process.stdin.on('keypress', onKeypress);
      rl.on('SIGINT', () => { rl.close(); finish('reject'); });

      const hint = defaultVal ? ` (${DIM}${defaultVal}${RESET})` : '';
      rl.question(`${YELLOW}${prompt}${RESET}${hint}: `, answer => {
        finish('resolve', answer.trim() || defaultVal);
      });
    });
  }

  setMsg(msg, color = GREEN) {
    this.message = msg;
    this.messageColor = color;
  }

  moveUp() {
    if (this.cursor > 0) {
      this.cursor--;
      if (this.cursor < this.offset) this.offset = this.cursor;
    }
  }

  moveDown() {
    if (this.cursor < this.filteredConnections.length - 1) {
      this.cursor++;
      const maxVisible = this.visibleRows;
      if (this.cursor >= this.offset + maxVisible) this.offset = this.cursor - maxVisible + 1;
    }
  }

  connect() {
    const filtered = this.filteredConnections;
    if (filtered.length === 0) return;
    const c = filtered[this.cursor];
    this.cleanup();
    clearScreen();
    showCursor();
    console.log(`\n${CYAN}Connecting to ${BOLD}${c.Host}${RESET}${CYAN} (${c.User}@${c.HostName})...${RESET}\n`);

    const args = ['-F', CONFIG_FILE, c.Host];
    const proc = spawn('ssh', args, { stdio: 'inherit' });
    proc.on('exit', () => {
      console.log(`\n${DIM}Connection closed. Run the app again to reconnect.${RESET}\n`);
      showCursor();
      process.exit(0);
    });
  }

  async addConnection() {
    showCursor();
    this.cleanup();
    clearScreen();

    print(BOLD + CYAN + 'Add new SSH connection\n' + RESET);
    print(DIM + '─'.repeat(40) + RESET + '\n\n');

    try {
      const host     = await this.askField('Name / alias (Host)');
      if (!host) { this.setMsg('Cancelled.', DIM); this.setup(); this.render(); return; }
      const hostname = await this.askField('Hostname / IP');
      if (!hostname) { this.setMsg('Cancelled.', DIM); this.setup(); this.render(); return; }
      const user     = await this.askField('Username', process.env.USER || 'root');
      const port     = await this.askField('Port', '22');
      const identity = await this.askField('IdentityFile (optional)');

      const entry = { Host: host, HostName: hostname, User: user };
      if (port && port !== '22') entry.Port = port;
      if (identity) entry.IdentityFile = identity;

      this.connections.push(entry);
      saveConnections(this.connections);
      this.cursor = this.connections.length - 1;
      this.searchQuery = '';
      this.offset = 0;
      this.setMsg(`Added: ${host}`);
    } catch {
      this.setMsg('Cancelled.', DIM);
    }

    hideCursor();
    this.setup();
    this.render();
  }

  async editConnection() {
    const filtered = this.filteredConnections;
    if (filtered.length === 0) return;
    const c = filtered[this.cursor];
    const originalIdx = this.connections.indexOf(c);

    showCursor();
    this.cleanup();
    clearScreen();

    print(BOLD + CYAN + `Edit connection: ${c.Host}\n` + RESET);
    print(DIM + '─'.repeat(40) + RESET + '\n\n');

    try {
      const host     = await this.askField('Name / alias', c.Host);
      const hostname = await this.askField('Hostname / IP', c.HostName || '');
      const user     = await this.askField('Username', c.User || '');
      const port     = await this.askField('Port', c.Port || '22');
      const identity = await this.askField('IdentityFile (optional)', c.IdentityFile || '');

      const entry = { Host: host, HostName: hostname, User: user };
      if (port && port !== '22') entry.Port = port;
      if (identity) entry.IdentityFile = identity;

      this.connections[originalIdx] = entry;
      saveConnections(this.connections);
      this.setMsg(`Updated: ${host}`);
    } catch {
      this.setMsg('Cancelled.', DIM);
    }

    hideCursor();
    this.setup();
    this.render();
  }

  deleteConnection() {
    const filtered = this.filteredConnections;
    if (filtered.length === 0) return;
    const c = filtered[this.cursor];
    this.pendingDelete = true;
    this.setMsg(`Delete "${c.Host}"? Y to confirm, any other key to cancel.`, RED);
    this.render();
  }

  doDelete() {
    const filtered = this.filteredConnections;
    if (filtered.length === 0) return;
    const c = filtered[this.cursor];
    const originalIdx = this.connections.indexOf(c);
    this.connections.splice(originalIdx, 1);
    const newFiltered = this.filteredConnections;
    if (this.cursor >= newFiltered.length) this.cursor = Math.max(0, newFiltered.length - 1);
    saveConnections(this.connections);
    this.setMsg(`Deleted: ${c.Host}`, YELLOW);
    this.render();
  }

  onKey(key) {
    if (this.pendingDelete) {
      this.pendingDelete = false;
      if (key === 'y' || key === 'Y') {
        this.doDelete();
      } else {
        this.setMsg('Delete cancelled.', DIM);
        this.render();
      }
      return;
    }

    this.message = '';

    if (key === '\u001b[A') { this.moveUp(); this.render(); }       // Arrow Up
    else if (key === '\u001b[B') { this.moveDown(); this.render(); } // Arrow Down
    else if (key === '\r' || key === '\n') { this.connect(); }       // Enter
    else if (key === '\x0e') { this.addConnection(); }              // Ctrl+N
    else if (key === '\x05') { this.editConnection(); }             // Ctrl+E
    else if (key === '\x04') { this.deleteConnection(); }           // Ctrl+D
    else if (key === '\u0003') { this.quit(); }                     // Ctrl+C
    else if (key === '\u001b') {                                    // Escape
      if (this.searchQuery) {
        this.searchQuery = ''; this.cursor = 0; this.offset = 0; this.render();
      } else {
        this.quit();
      }
    }
    else if (key === '\u007f') {                                    // Backspace
      if (this.searchQuery.length > 0) {
        this.searchQuery = this.searchQuery.slice(0, -1);
        this.cursor = 0; this.offset = 0;
      }
      this.render();
    }
    else if (key.length === 1 && key >= ' ') {                     // Printable → search
      this.searchQuery += key;
      this.cursor = 0; this.offset = 0;
      this.render();
    }
    else { this.render(); }
  }

  setup() {
    process.stdin.setRawMode(true);
    process.stdin.resume();
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', this._keyHandler = (key) => this.onKey(key));
  }

  cleanup() {
    process.stdin.removeListener('data', this._keyHandler);
    process.stdin.setRawMode(false);
    process.stdin.pause();
  }

  quit() {
    this.cleanup();
    showCursor();
    clearScreen();
    print(DIM + 'Bye!\n' + RESET);
    process.exit(0);
  }

  run() {
    hideCursor();
    this.setup();
    this.render();
  }
}

// ── Direct connect (argument mode) ───────────────────────────────────────────

const arg = process.argv[2];
if (arg) {
  const connections = loadConnections();
  const match = connections.find(c => c.Host.toLowerCase() === arg.toLowerCase());
  if (!match) {
    console.error(`${RED}No connection found: "${arg}"${RESET}`);
    console.error(`${DIM}Available: ${connections.map(c => c.Host).join(', ')}${RESET}`);
    process.exit(1);
  }
  console.log(`\n${CYAN}Connecting to ${BOLD}${match.Host}${RESET}${CYAN} (${match.User}@${match.HostName})...${RESET}\n`);
  const proc = spawn('ssh', ['-F', CONFIG_FILE, match.Host], { stdio: 'inherit' });
  proc.on('exit', () => process.exit(0));
} else {
  new SSHManager().run();
}
