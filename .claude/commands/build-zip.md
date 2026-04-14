# /build-zip

Build the HealthOS installer ZIP for upload to S3.

Run this exact command — do not construct the zip command manually:

```bash
cd "/Users/pyost/PY Clients/Yost Advantage Inc/HealthOS" && \
zip -r "/tmp/healthos-installer.zip" "HealthOS-Installer/" \
  --exclude "HealthOS-Installer/.git/*" \
  --exclude "HealthOS-Installer/.gitignore" \
  --exclude "HealthOS-Installer/INSTALLER-DEV-NOTES.md" \
  --exclude "HealthOS-Installer/categories-preferences-data.txt" \
  --exclude "HealthOS-Installer/reference/*" \
  --exclude "HealthOS-Installer/scripts/reboot_healthos.py"
```

When done, confirm:
- Output file: `/tmp/healthos-installer.zip`
- File size
- List exactly what was included (no dev files, no .git)

Then tell Paul: "Upload `/tmp/healthos-installer.zip` to S3 bucket `healthos-installer-dist-258616130987-us-east-1-an` as `healthos-installer.zip`."
