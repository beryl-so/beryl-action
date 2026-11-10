# Beryl tests

Upload an Android or iOS build to Beryl, run the project's Beryl tests, and fail the job when the run fails.

```yaml
- uses: beryl-so/beryl-action@v1
  with:
    token: ${{ secrets.BERYL_CI_TOKEN }}
    workspace: <workspace id>
    project: <project id>
    build: app/build/outputs/apk/release/app-release.apk
```

Inputs, outputs and an Expo EAS example: https://beryl.so/docs/ci#github-action
