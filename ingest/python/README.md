# Bundled Python Runtime

Place the bundled Python distribution here so Tauri can ship it as a resource.
The app will prefer this runtime over system Python and still run:

```
pip install --upgrade kumiho
```

Expected layout:

- `python/windows/python.exe`
- `python/macos/bin/python3`
- `python/linux/bin/python3`

Adjust the runtime packaging to match your distribution tooling.
