# Contributing

Thanks for helping improve LocalOpsConsole. This project is free and open source under the MIT License.

## How to contribute

1. Fork the repo and create a branch from `main`.
2. Keep changes focused (one feature or fix per PR when practical).
3. Match existing PowerShell 5.1 style and avoid PowerShell 7-only syntax (`??`, `?:`, etc.).
4. Test locally: `.\start.bat`, exercise the module you touched, then `.\build.ps1`.
5. Open a pull request with a short summary of **why** and how you tested.

## Module guidelines

- Each module lives under `modules/<Name>/` with `module.json`, `diagnostics/`, `actions/`, optional `lib/`.
- Prefer fast CIM/local commands for anything on the telemetry path.
- Mark mutating actions in `requiresAdmin` when elevation is required.
- Document new modules in `docs/USER_GUIDE.md` and the local marketing docs under `website/` (hosted at opsconsole.co.za; not tracked on GitHub).

## Security

See [SECURITY.md](SECURITY.md). Do not disclose vulnerabilities in public issues.
