# Apple Developer Certificate Setup for macOS Code Signing

This guide explains how to create, export, and configure an Apple Developer ID Application certificate for signing the Kumiho Browser macOS app via GitHub Actions.

## Prerequisites

- Active **Apple Developer Program** membership ($99/year)
- macOS computer with **Xcode** installed
- Access to the GitHub repository secrets

---

## Part 1: Create a Developer ID Application Certificate

If you already have a "Developer ID Application" certificate with its private key in Keychain Access, skip to [Part 2](#part-2-locate-certificate-in-keychain-access).

### Step 1.1: Open Xcode Preferences

1. Open **Xcode**
2. Go to **Xcode → Settings** (or press `⌘ + ,`)
3. Click the **Accounts** tab

### Step 1.2: Add Your Apple ID (if not already added)

1. Click the **+** button at the bottom left
2. Select **Apple ID**
3. Sign in with your Apple Developer account credentials

### Step 1.3: Manage Certificates

1. Select your Apple ID from the list
2. Select your **Team** (the one with the Team ID you want to use)
3. Click **Manage Certificates...**

### Step 1.4: Create the Certificate

1. Click the **+** button in the bottom left of the certificates sheet
2. Select **Developer ID Application**
3. Xcode will automatically:
   - Generate a private key on your Mac
   - Create a Certificate Signing Request (CSR)
   - Submit to Apple
   - Download and install the certificate

4. You should now see **"Developer ID Application: Your Name (TEAM_ID)"** in the list

> ⚠️ **Important**: The private key is created and stored ONLY on this Mac. If you lose it, you'll need to revoke and create a new certificate.

---

## Part 2: Locate Certificate in Keychain Access

### Step 2.1: Open Keychain Access

1. Open **Keychain Access** (use Spotlight: `⌘ + Space`, type "Keychain Access")
2. In the left sidebar, ensure **"login"** keychain is selected
3. Click **"My Certificates"** in the Category section

### Step 2.2: Find Your Certificate

1. Look for **"Developer ID Application: Your Name (TEAM_ID)"**
2. **Click the triangle** (▶) next to the certificate to expand it
3. You **MUST** see a **private key** underneath the certificate

```
▼ Developer ID Application: Your Name (M57TZEKD3W)
    🔑 Your Name
```

> ⚠️ **If there's NO private key**: The certificate cannot be used for signing. You need to create a new certificate on the Mac where you want the private key to reside (see Part 1).

---

## Part 3: Export Certificate as .p12

### Step 3.1: Select the Certificate

1. In Keychain Access → My Certificates
2. **Right-click** on **"Developer ID Application: Your Name (TEAM_ID)"**
   - Make sure you click on the certificate itself, not the private key
3. Select **"Export..."**

### Step 3.2: Save as .p12 Format

1. In the save dialog:
   - **Save As**: `developer_id_application.p12` (or any name you prefer)
   - **Where**: Desktop (or any easily accessible location)
   - **File Format**: **Personal Information Exchange (.p12)** ← This is critical!

2. Click **Save**

### Step 3.3: Set a Password

1. You'll be prompted to create a password for the .p12 file
2. Enter a **strong password** and confirm it
3. **Remember this password** - you'll need it for `APPLE_CERTIFICATE_PASSWORD`
4. Click **OK**

5. You may be prompted for your macOS login password to allow the export - enter it

### Step 3.4: Verify the Export

The file should be around 3-6 KB. If it's suspiciously small (< 1 KB), the private key may not have been included.

---

## Part 4: Convert to Base64

### Step 4.1: Open Terminal

1. Open **Terminal** (Spotlight: `⌘ + Space`, type "Terminal")

### Step 4.2: Navigate to the File

```bash
cd ~/Desktop  # or wherever you saved the .p12 file
```

### Step 4.3: Convert to Base64 and Copy to Clipboard

```bash
base64 -i developer_id_application.p12 | pbcopy
```

This command:
- Reads the .p12 file
- Converts it to base64 encoding
- Copies the result directly to your clipboard

> 💡 **Tip**: To verify the output length, you can run:
> ```bash
> base64 -i developer_id_application.p12 | wc -c
> ```
> It should be several thousand characters (typically 4000-8000).

---

## Part 5: Update GitHub Secrets

### Step 5.1: Navigate to Repository Secrets

1. Go to your GitHub repository
2. Click **Settings** (tab at the top)
3. In the left sidebar, click **Secrets and variables** → **Actions**
4. You'll see a list of repository secrets

### Step 5.2: Update APPLE_CERTIFICATE_BASE64

1. Find **`APPLE_CERTIFICATE_BASE64`** in the list
2. Click **Update** (pencil icon)
3. **Paste** the clipboard contents (the base64 string from Part 4)
4. Click **Update secret**

> ⚠️ **Do NOT** include any extra whitespace, newlines, or quotes around the value.

### Step 5.3: Update APPLE_CERTIFICATE_PASSWORD

1. Find **`APPLE_CERTIFICATE_PASSWORD`** in the list
2. Click **Update**
3. Enter the **exact password** you set in Step 3.3
4. Click **Update secret**

### Step 5.4: Verify Other Required Secrets

Ensure these secrets are also configured:

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `APPLE_TEAM_ID` | Your 10-character Team ID | `M57TZEKD3W` |
| `APPLE_ID` | Your Apple ID email | `developer@example.com` |
| `APPLE_APP_PASSWORD` | App-specific password (see below) | `xxxx-xxxx-xxxx-xxxx` |

---

## Part 6: Create App-Specific Password (for Notarization)

Apple requires an app-specific password for notarization (not your regular Apple ID password).

### Step 6.1: Go to Apple ID Settings

1. Visit [appleid.apple.com](https://appleid.apple.com)
2. Sign in with your Apple ID

### Step 6.2: Generate App-Specific Password

1. In the **Sign-In and Security** section, click **App-Specific Passwords**
2. Click **Generate an app-specific password** (or the **+** button)
3. Enter a label: `GitHub Actions Notarization`
4. Click **Create**
5. **Copy the generated password** (format: `xxxx-xxxx-xxxx-xxxx`)

### Step 6.3: Save to GitHub Secrets

1. Go to your GitHub repository → Settings → Secrets → Actions
2. Update **`APPLE_APP_PASSWORD`** with the generated password

---

## Part 7: Test the Configuration

### Step 7.1: Trigger a Build

1. Go to **Actions** tab in your GitHub repository
2. Select **"Build Kumiho Browser Desktop Apps"** workflow
3. Click **"Run workflow"**
4. Select **production** environment
5. Click **"Run workflow"**

### Step 7.2: Verify Signing Success

In the build logs, look for:

```
==> Importing Apple Developer certificate
==> Available signing identities:
  1) ABC123DEF456... "Developer ID Application: Your Name (M57TZEKD3W)"
     1 valid identities found
==> Found signing identity: Developer ID Application: Your Name (M57TZEKD3W)
...
==> Codesigning app with: Developer ID Application: Your Name (M57TZEKD3W)
==> Code signing complete
...
==> Submitting DMG for notarization
==> Stapling notarization ticket to DMG
==> Notarization complete
```

### Step 7.3: Verify on macOS

After downloading the built .dmg:

1. Open the .dmg and drag the app to Applications
2. The app should open **without** "unidentified developer" warnings
3. To verify the signature:
   ```bash
   codesign -dv --verbose=4 "/Applications/Kumiho Browser.app" 2>&1 | grep Authority
   ```
   Should show:
   ```
   Authority=Developer ID Application: Your Name (M57TZEKD3W)
   Authority=Developer ID Certification Authority
   Authority=Apple Root CA
   ```

---

## Troubleshooting

### "0 valid identities found"

**Cause**: The .p12 file doesn't contain the private key.

**Fix**: Re-export from Keychain Access, ensuring you:
1. Select the certificate under "My Certificates"
2. See the private key (🔑) underneath when expanded
3. Export as .p12 format

### "The specified item could not be found in the keychain"

**Cause**: Certificate import failed or password mismatch.

**Fix**:
1. Verify `APPLE_CERTIFICATE_PASSWORD` matches exactly what you set during export
2. Re-export the certificate and update both secrets

### "Developer ID Application certificate not found"

**Cause**: You may have exported a different certificate type.

**Fix**: Ensure you're exporting specifically the **"Developer ID Application"** certificate, not:
- "Developer ID Installer" (different purpose)
- "Apple Development" (for debug builds only)
- "Apple Distribution" (for App Store, not direct distribution)

### Notarization fails with "Invalid credentials"

**Cause**: Wrong Apple ID credentials or app-specific password.

**Fix**:
1. Verify `APPLE_ID` is your correct Apple Developer account email
2. Generate a **new** app-specific password and update `APPLE_APP_PASSWORD`
3. Ensure `APPLE_TEAM_ID` matches your certificate's team

---

## Security Best Practices

1. **Never commit** the .p12 file or base64 string to git
2. **Delete** the .p12 file from your Mac after uploading to GitHub Secrets
3. **Rotate** app-specific passwords periodically
4. **Limit** repository secret access to trusted team members
5. **Revoke** and recreate certificates if you suspect compromise

---

## Certificate Renewal

Apple Developer ID certificates are valid for **5 years**. Before expiration:

1. Create a new certificate (Part 1)
2. Export and update secrets (Parts 3-5)
3. The old certificate can remain until all existing signed apps are updated

---

## Quick Reference: Required GitHub Secrets

| Secret | Source | Notes |
|--------|--------|-------|
| `APPLE_CERTIFICATE_BASE64` | Keychain Access → Export .p12 → base64 | Must include private key |
| `APPLE_CERTIFICATE_PASSWORD` | Set during .p12 export | Can be empty if exported without password |
| `APPLE_TEAM_ID` | Apple Developer account | 10-character ID (e.g., `M57TZEKD3W`) |
| `APPLE_ID` | Your Apple ID | Email used for Apple Developer account |
| `APPLE_APP_PASSWORD` | appleid.apple.com | App-specific password, not your login password |
