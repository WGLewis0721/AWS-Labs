# prod environment

This directory is a placeholder environment root. It is not the active lab and it is not currently documented as production-ready.

## Current Status

- the validated environment is `environments/dev`
- this directory should be treated as future-work scaffolding
- prompts and skills should not assume `prod` matches `dev` unless the user explicitly asks to promote the architecture

## If You Intend To Build Production

Before using this environment:

1. define a separate backend and state strategy
2. define production-specific inputs and tagging
3. decide whether golden AMIs, S3 bootstrap assets, and SSM netchecks are part of the production deployment path
4. review public exposure, management CIDRs, and operator workflow explicitly
5. document any differences from the `dev` direct private-IP validation model

Until then, treat this directory as a placeholder rather than an executable environment definition.
