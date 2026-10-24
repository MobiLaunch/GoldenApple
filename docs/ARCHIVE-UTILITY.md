# Archive Utility

CitronOS Archive Utility is a native Qt/Quickshell application using the same
shared AppWindow, typography, symbol library, toolbar, and settings as Files.

## Supported formats

- **Read and extract:** .zip, .cbz, .tar, .tar.gz / .tgz,
  .tar.bz2 / .tbz / .tbz2, and .tar.xz / .txz.
- **Create:** .zip files from files and folders, without proprietary codecs.
- **Not yet supported:** .rar, .7z, password-protected ZIP archives and
  self-extracting EXE files. Unsupported types return a clear error instead
  of silently claiming successful extraction.

## Usage

Double-click an archive in **Files** to browse contents in Archive Utility.
Choose **Extract** to place the contents inside a separate folder adjacent
to the archive, or **Extract to…** to select another destination. The
original archive is never changed. Press **⌘O** to choose an archive and
**⌘E** to extract; the Cancel button interrupts work.

In Files, right-click an archive and select **Extract Here**, or select
one or more files/folders and choose **Compress to ZIP**. Both operations
run outside the UI thread. The new ZIP/folder appears in Files when done.

The viewer also supports **Create ZIP…** for selecting ordinary files.
Selecting folders for compression is supported through the Files context menu.

CLI:

```sh
gg-archive ~/Downloads/example.zip
python3 /usr/share/golden-gate/apps/archive/helper.py inspect ~/Downloads/example.zip
python3 /usr/share/golden-gate/apps/archive/helper.py extract ~/Downloads/example.zip
python3 /usr/share/golden-gate/apps/archive/helper.py extract ~/Downloads/example.zip ~/Desktop
gg-archive --create ~/Documents/Notes ~/Documents/Photos
```

The command-line backend emits one JSON message per line, including progress
and a final success/error result. It never executes archive member names.

## Safety and limits

All member names are inspected before files are written. Extraction rejects
absolute paths, parent traversal, symbolic/hard links, device nodes, duplicate
files and unsafe entries. It enforces a 100,000-member, 8 GiB total-size,
4 GiB per-file and suspicious-compression-ratio limit. The extraction takes
place in a private temporary directory, then uses Linux `renameat2`
with `RENAME_NOREPLACE` to publish the completed folder atomically.
Existing data is never overwritten, including if another process creates
the target folder during extraction. Cancellation removes temporary contents.

This is a deliberate conservative policy: archives containing symlinks may
be refused instead of silently creating a link outside the extraction folder.

Run `python3 tests/archive-utility.py` to exercise ZIP/TAR round trips and
path traversal, symlink, duplicate-name, and name-collision protections.
