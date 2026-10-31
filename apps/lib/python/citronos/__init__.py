"""citronos: what CitronOS's Python helpers share (T-2.4).

    files    atomic writes (file and folder synced), JSON, locks, keeping a
             damaged file aside
    secrets  the login keyring (Secret Service), with clear errors
    jsonl    append-only JSON-lines logs that survive a torn last line
    proc     child processes with a timeout, never a shell, gone with their parent
    paths    the XDG folders, and CitronOS's own under them

A helper finds it beside the app folders, in apps/lib/python (installed:
/usr/share/golden-gate/ui/python):

    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib/python"))
    from citronos import files
"""
