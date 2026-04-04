# Amazon Q Developer VS Code Setup

Date: 2026-04-04
Workspace: `C:\Users\Willi\projects\Labs`

## Steps Taken

1. Read required session instructions:
   - `artifacts/prompts/copilot-instructions-v1.md`
   - `artifacts/prompts/Seasoning.md`
2. Reviewed available local skill files under `artifacts/skills`.
3. Verified local VS Code installation:
   - `C:\Users\Willi\AppData\Local\Programs\Microsoft VS Code\Code.exe`
   - version `1.114.0`
4. Verified the official Amazon Q Developer for VS Code install target:
   - Marketplace item: `AmazonWebServices.amazon-q-vscode`
   - Official docs confirm VS Code support and sign-in flow.
5. Attempted CLI verification with `code`, then corrected to `code.cmd` because PowerShell resolved `code` to `Code.exe`.
6. Confirmed Amazon Q is already installed globally in VS Code:
   - extension folder: `C:\Users\Willi\.vscode\extensions\amazonwebservices.amazon-q-vscode-2.0.0`
   - installed extension version: `amazonwebservices.amazon-q-vscode@2.0.0`
7. Checked for existing VS Code Amazon Q state:
   - Amazon Q settings already exist in `AppData\Roaming\Code\User\settings.json`
   - Amazon Q global storage folder already exists

## Fixes Applied

- No reinstall was necessary because Amazon Q was already installed.
- Corrected the CLI invocation from `code` to `code.cmd` so VS Code extension commands work properly on this Windows setup.

## Problems Encountered

- `code` resolved to `Code.exe`, which rejected CLI flags such as `--install-extension` and `--list-extensions`.
- Existing Amazon Q settings show prior usage, so this session could verify installation but could not complete interactive browser authentication headlessly from the terminal.

## Recommended Next Steps

1. In VS Code, click the Amazon Q icon in the activity bar.
2. Sign in with one of the supported methods:
   - AWS Builder ID for free tier/personal use
   - IAM Identity Center for Amazon Q Developer Pro
3. If the chat view does not appear, open the Command Palette and run `Amazon Q: Open Chat`.
4. If sign-in looks stale, sign out from Amazon Q inside VS Code and sign back in.

## Sources Used

- AWS docs: https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/q-in-IDE-setup.html
- VS Code Marketplace: https://marketplace.visualstudio.com/items?itemName=AmazonWebServices.amazon-q-vscode
