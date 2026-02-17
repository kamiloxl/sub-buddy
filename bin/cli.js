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

function isRunning() {
  try {
    const result = execSync(
      `pgrep -f "${BUNDLE_NAME}" 2>/dev/null`,
      { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }
    );
    return result.trim().length > 0;
  } catch {
    return false;
  }
}

function start() {
  if (!fs.existsSync(APP_PATH)) {
    console.error(`${APP_NAME} is not installed at ${APP_PATH}`);
    console.error('Run: npm install -g sub-buddy');
    process.exit(1);
  }

  if (isRunning()) {
    console.log(`${APP_NAME} is already running.`);
    return;
  }

  console.log(`Starting ${APP_NAME}...`);
  execSync(`open "${APP_PATH}"`);
  console.log(`${APP_NAME} started.`);
}

function stop() {
  if (!isRunning()) {
    console.log(`${APP_NAME} is not running.`);
    return;
  }

  console.log(`Stopping ${APP_NAME}...`);
  try {
    execSync(`osascript -e 'quit app "${APP_NAME}"'`);
    console.log(`${APP_NAME} stopped.`);
  } catch {
    console.error(`Could not stop ${APP_NAME}. Try: killall "Sub Buddy"`);
    process.exit(1);
  }
}

function status() {
  const installed = fs.existsSync(APP_PATH);
  const running = isRunning();
  const autostartEnabled = fs.existsSync(PLIST_PATH);

  console.log(`${APP_NAME}`);
  console.log(`  Installed:  ${installed ? 'yes' : 'no'}${installed ? ` (${APP_PATH})` : ''}`);
  console.log(`  Running:    ${running ? 'yes' : 'no'}`);
  console.log(`  Autostart:  ${autostartEnabled ? 'on' : 'off'}`);
}

function autostartOn() {
  if (!fs.existsSync(APP_PATH)) {
    console.error(`${APP_NAME} is not installed. Install it first.`);
    process.exit(1);
  }

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

  fs.writeFileSync(PLIST_PATH, plist, 'utf8');

  try {
    execSync(`launchctl load "${PLIST_PATH}" 2>/dev/null`);
  } catch {
    // Already loaded — not an error
  }

  console.log('Autostart enabled. Sub Buddy will launch at login.');
}

function autostartOff() {
  if (fs.existsSync(PLIST_PATH)) {
    try {
      execSync(`launchctl unload "${PLIST_PATH}" 2>/dev/null`);
    } catch {
      // Not loaded — not an error
    }
    fs.unlinkSync(PLIST_PATH);
  }

  console.log('Autostart disabled.');
}

function uninstall() {
  console.log(`Uninstalling ${APP_NAME}...`);

  stop();
  autostartOff();

  if (fs.existsSync(APP_PATH)) {
    fs.rmSync(APP_PATH, { recursive: true, force: true });
    console.log(`Removed ${APP_PATH}`);
  }

  console.log(`${APP_NAME} uninstalled.`);
  console.log('Now remove the npm package: npm uninstall -g sub-buddy');
}

function showHelp() {
  console.log(`
  Sub Buddy — macOS menu bar app for RevenueCat metrics

  Usage:
    sub-buddy start          Launch the app
    sub-buddy stop           Quit the app
    sub-buddy status         Show install and running status
    sub-buddy autostart on   Enable launch at login
    sub-buddy autostart off  Disable launch at login
    sub-buddy uninstall      Remove app, autostart, then run:
                             npm uninstall -g sub-buddy
    sub-buddy help           Show this message
`);
}

// --- Main ---

if (process.platform !== 'darwin') {
  console.error('Sub Buddy is only available on macOS.');
  process.exit(1);
}

const [command, subcommand] = process.argv.slice(2);

switch (command) {
  case 'start':
    start();
    break;
  case 'stop':
    stop();
    break;
  case 'status':
    status();
    break;
  case 'autostart':
    if (subcommand === 'on') autostartOn();
    else if (subcommand === 'off') autostartOff();
    else {
      console.error('Usage: sub-buddy autostart on|off');
      process.exit(1);
    }
    break;
  case 'uninstall':
    uninstall();
    break;
  case 'help':
  case '--help':
  case '-h':
  case undefined:
    showHelp();
    break;
  default:
    console.error(`Unknown command: ${command}`);
    showHelp();
    process.exit(1);
}
