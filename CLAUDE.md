# HealthOS Installer

This workspace installs HealthOS on AWS Lightsail — a personal AI health coach that runs 24/7 in the cloud.

## How to Use

Type `/install` and press Enter. Claude will guide you through the entire setup.

## What You Need Before Starting

- An AWS account (or Claude will help you create one — it's free for 90 days)
- Telegram on your phone (free, App Store or Google Play)
- An Anthropic API key (get one at console.anthropic.com)

## Building the Installer ZIP

**To build the ZIP for S3 upload, always use `/build-zip` — never construct the zip command manually.**

This ensures the correct filename (`healthos-installer.zip`), correct source path, and correct exclude list every time.

## Scripts

All installer scripts are in `scripts/`. Claude runs them automatically — do not modify them.

## Support

If something goes wrong, Claude will tell you exactly what happened and how to fix it.
