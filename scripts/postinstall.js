#!/usr/bin/env node

'use strict';

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const APP_NAME = 'Sub Buddy';
const BUNDLE_NAME = 'Sub Buddy.app';
const INSTALL_DIR = path.join(os.homedir(), 'Applications');
const APP_PATH = path.join(INSTALL_DIR, BUNDLE_NAME);
const PLIST_NAME = 'com.subbuddy.app.plist';
const LAUNCH_AGENTS_DIR = path.join(os.homedir(), 'Library', 'LaunchAgents');
const PLIST_PATH = path.join(LAUNCH_AGENTS_DIR, PLIST_NAME);

// Resolve the dist directory relative to the package root
const PACKAGE_ROOT = path.resolve(__dirname, '..');
const DIST_APP = path.join(PACKAGE_ROOT, 'dist', BUNDLE_NAME);

function log(msg) {
  console.log(`  sub-buddy: ${msg}`);
}

function fail(msg) {
  console.error(`  sub-buddy: ${msg}`);
  process.exit(1);
}

// --- Checks ---

if (process.platform !== 'darwin') {
  log('Skipping installation — Sub Buddy is only available on macOS.');
  process.exit(0);
}

if (!fs.existsSync(DIST_APP)) {
  fail(`Built app not found at ${DIST_APP}. The package may be corrupted.`);
}

// --- Stop previous version if running ---

try {
  execSync(`pgrep -f "${BUNDLE_NAME}" >/dev/null 2>&1`, { stdio: 'pipe' });
  log('Stopping previous version...');
  try {
    execSync(`osascript -e 'quit app "${APP_NAME}"' 2>/dev/null`, { stdio: 'pipe' });
  } catch {
    // Graceful quit failed — force kill
    try {
      execSync(`pkill -f "${BUNDLE_NAME}" 2>/dev/null`, { stdio: 'pipe' });
    } catch {
      // Process already gone
    }
  }
  // Brief wait for the app to fully quit
  execSync('sleep 1');
} catch {
  // App not running — nothing to stop
}

// --- Install .app to ~/Applications ---

log(`Installing to ${APP_PATH}...`);
fs.mkdirSync(INSTALL_DIR, { recursive: true });

if (fs.existsSync(APP_PATH)) {
  fs.rmSync(APP_PATH, { recursive: true, force: true });
}

// Copy the .app bundle
execSync(`cp -R "${DIST_APP}" "${INSTALL_DIR}/"`);
log('Application installed.');

// --- Set up LaunchAgent for autostart ---

log('Setting up autostart...');
fs.mkdirSync(LAUNCH_AGENTS_DIR, { recursive: true });

const plist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.subbuddy.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>${APP_NAME}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
`;

// Unload old agent if present
if (fs.existsSync(PLIST_PATH)) {
  try {
    execSync(`launchctl unload "${PLIST_PATH}" 2>/dev/null`, { stdio: 'pipe' });
  } catch {
    // Not loaded — fine
  }
}

fs.writeFileSync(PLIST_PATH, plist, 'utf8');

try {
  execSync(`launchctl load "${PLIST_PATH}" 2>/dev/null`, { stdio: 'pipe' });
} catch {
  // Load can fail in certain contexts (e.g. CI) — non-fatal
  log('Could not register autostart (this is normal in non-interactive environments).');
}

log('Autostart configured — Sub Buddy will launch at login.');

// --- Launch the app ---

log('Launching Sub Buddy...');
try {
  execSync(`open "${APP_PATH}"`);
  log('Sub Buddy is running. Look for the chart icon in your menu bar.');
} catch {
  log('Could not launch automatically. Run: sub-buddy start');
}

log('Done. Run "sub-buddy help" for available commands.');
log('To uninstall: sub-buddy uninstall && npm uninstall -g sub-buddy');
