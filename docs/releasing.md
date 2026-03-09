# Releasing

## One-time Sparkle setup

The Sparkle tools ship inside DerivedData after the first build:

```
~/Library/Developer/Xcode/DerivedData/Yap-*/SourcePackages/artifacts/sparkle/Sparkle/bin/
```

Generate your EdDSA key pair once:

```bash
<path>/generate_keys
```

It stores the private key in your Keychain and prints the public key. Paste the public key directly into `project.yml` under `SUPublicEDKey`, then run `xcodegen generate`. The public key is safe to commit — only the private key (Keychain) must stay secret.

## Each release

**1. Build and zip:**
```bash
xcodegen generate && ./scripts/release.sh
```

**2. Sign and update the appcast:**
```bash
<path>/generate_appcast --download-url-prefix "https://github.com/zainzafar90/yap/releases/download/X.Y.Z/" .
```

Commit the updated appcast:

```bash
git add appcast.xml && git commit -m "chore: appcast vX.Y.Z"
```

**3. Upload** both `Yap-X.Y.Z.dmg` and `Yap-X.Y.Z.zip` to GitHub Releases. The DMG is for users downloading manually. The zip is for Sparkle auto-updates — point the appcast `url` at the zip.

**4. Bump version** in `project.yml` (`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`) for the next cycle.
