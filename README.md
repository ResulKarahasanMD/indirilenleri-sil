# İndirilenleri Sil

A macOS tool that removes from disk the local copies of files already uploaded to iCloud Drive: a Finder toolbar button, a Services entry and a command line. Files stay in iCloud; they download again when you open them. It stands in for the `brctl evict` command, which no longer exists on current macOS.

## What it does and doesn't do

- It scans the files and folders you select, shows the candidates whose local copies can be removed and the space that will be freed, and removes them after you confirm.
- It deletes nothing from iCloud. It doesn't touch files outside iCloud.
- It skips the following and reports why: files not yet uploaded or still uploading, recently modified files, open files, files with conflicts, items pinned with "Keep Downloaded", containers of apps that download their own content back, and files the system refuses to evict.
- Every run writes a log (TSV) under `~/Library/Logs/IndirilenleriSil/`. `--verify` checks whether the removed items have since downloaded again.

## Usage

- **Finder toolbar:** in Finder, choose View → Customize Toolbar and add the "İndirilenleri Sil" button. Select a file or folder and press the button.
- **Right-click:** "İndirilenleri Sil" under Services in the menu.
- **Command line:**

  ```bash
  APP=~/Applications/IndirilenleriSil.app/Contents/MacOS/IndirilenleriSil
  $APP --dry-run <yol…>            # scan, print a summary; nothing is removed (yol = path)
  $APP --list <yol…>               # also print candidate and skipped paths
  $APP --evict <yol…>              # scan and remove, keep a log
  $APP --verify <kayıt.tsv|last>   # are the removed items still in the cloud (kayıt = log)
  ```

  Exit status: 0 everything asked for was done; 1 something was left or could not be read; 2 (`--verify`) removed items have downloaded again; 64 wrong usage.

## Installation

Requirements: macOS 27.0.1 or later, Xcode 27, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and a Developer ID signing identity.

1. Replace the `DEVELOPMENT_TEAM` value in `Config/Shared.xcconfig` with your own team ID.
2. Run the `scripts/build-install.sh` script. The script makes a Release build, installs it as `~/Applications/IndirilenleriSil.app`, and registers and enables the Finder extension.
3. If the extension stays disabled, turn it on in the Finder extensions list in System Settings, or run this command: `pluginkit -e use -i com.rak.indirilenlerisil.FinderExt`
4. On first run, macOS asks for permission to access iCloud Drive, Desktop and Documents.

On its first run the script generates the `Config/Token.xcconfig` file with a random value. The app and the Finder extension share this value; the file is not committed to the repository.

## Test

```bash
xcodegen generate
xcodebuild test -project IndirilenleriSil.xcodeproj -scheme CoreTests \
  -derivedDataPath build/dd -destination 'platform=macOS,arch=arm64'
```

106 Swift Testing tests. The tests run in a temporary home directory with a fake iCloud layer (`Tests/Support/FakeCloud.swift`).

## Known limitations

- Finder doesn't give extensions a context menu in iCloud Drive folders; there, use the toolbar button or the Services entry.
- Removal is asynchronous: it can take a few seconds for a file to turn back into a placeholder.
- The system refuses to evict some files (`NSFileProviderErrorDomain -2008`); these appear in the report with the reason `iCloud bırakmaya izin vermiyor` ("iCloud does not allow eviction").

## License

[MIT](LICENSE).
