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

function log(msg) {
  console.log(`  sub-buddy: ${msg}`);
}

if (process.platform !== 'darwin') {
  process.exit(0);
}

// --- Stop the app if running ---

try {
  execSync(`pgrep -f "${BUNDLE_NAME}" >/dev/null 2>&1`, { stdio: 'pipe' });
  log('Stopping Sub Buddy...');
  try {
    execSync(`osascript -e 'quit app "${APP_NAME}"' 2>/dev/null`, { stdio: 'pipe' });
  } catch {
    try {
      execSync(`pkill -f "${BUNDLE_NAME}" 2>/dev/null`, { stdio: 'pipe' });
    } catch {
      // Process already gone
    }
  }
  execSync('sleep 1');
} catch {
  // App not running
}

// --- Remove LaunchAgent ---

if (fs.existsSync(PLIST_PATH)) {
  log('Removing autostart...');
  try {
    execSync(`launchctl unload "${PLIST_PATH}" 2>/dev/null`, { stdio: 'pipe' });
  } catch {
    // Not loaded
  }
  fs.unlinkSync(PLIST_PATH);
  log('Autostart removed.');
}

// --- Remove the .app ---

if (fs.existsSync(APP_PATH)) {
  log(`Removing ${APP_PATH}...`);
  fs.rmSync(APP_PATH, { recursive: true, force: true });
  log('Application removed.');
}

log('Sub Buddy uninstalled.');
