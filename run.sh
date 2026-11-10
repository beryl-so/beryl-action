#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "::error title=Beryl::$1"
  exit 1
}

[ -n "${BERYL_TOKEN:-}" ] || fail "The token input is empty. Pass the project CI token from a secret."
[ -n "${INPUT_WORKSPACE:-}" ] || fail "The workspace input is required."
[ -n "${INPUT_PROJECT:-}" ] || fail "The project input is required."
# The CLI prefers BERYL_API_KEY over BERYL_TOKEN; a job-level one would replace the input.
unset BERYL_API_KEY
command -v npm >/dev/null || fail "Node.js 20.19 or newer is required on the runner (actions/setup-node)."

prefix="${RUNNER_TEMP:-$(mktemp -d)}/beryl-cli"
npm install --prefix "$prefix" --no-audit --no-fund --loglevel=error \
  "@beryl-so/cli@${INPUT_CLI_VERSION:-latest}" >/dev/null
beryl="$prefix/node_modules/.bin/beryl"

scope=(--workspace "$INPUT_WORKSPACE" --project "$INPUT_PROJECT")
[ -n "${INPUT_ENV:-}" ] && scope+=(--env "$INPUT_ENV")

if [ -n "${INPUT_BUILD:-}" ]; then
  upload=(config files upload "$INPUT_BUILD" "${scope[@]}")
  # The CLI infers the kind from .apk, .aab and .app; an archive could be a fixture.
  case "$(printf '%s' "$INPUT_BUILD" | tr '[:upper:]' '[:lower:]')" in
    *.tar.gz | *.tgz | *.zip) upload+=(--kind ios_build) ;;
  esac
  echo "::group::Upload $INPUT_BUILD"
  "$beryl" "${upload[@]}"
  echo "::endgroup::"
fi

trigger=(runs trigger "${scope[@]}")
# One per line keeps a name with a comma whole; a single line may list names with commas.
groups="${INPUT_GROUP:-}"
case "$groups" in
  *$'\n'*) ;;
  *) groups="$(printf '%s' "$groups" | tr ',' '\n')" ;;
esac
while IFS= read -r group; do
  group="$(printf '%s' "$group" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [ -n "$group" ] && trigger+=(--group "$group")
done < <(printf '%s\n' "$groups")

created="$("$beryl" --json "${trigger[@]}")" || {
  rc=$?
  echo "::error title=Beryl::beryl runs trigger failed (exit $rc); the CLI's message is above."
  exit "$rc"
}
run_id="$(printf '%s' "$created" | node -e '
  let s = "";
  process.stdin.on("data", (d) => (s += d)).on("end", () => {
    const id = JSON.parse(s).id;
    if (!id) process.exit(1);
    process.stdout.write(id);
  });
')" || fail "runs trigger returned no run id: $created"

case "$(printf '%s' "${BERYL_API_URL:-https://api.beryl.so}" | sed -E 's#^[a-z]+://##; s#[/:].*##')" in
  api.beryl.so) web="https://beryl.so" ;;
  dev.beryl.so) web="https://preview.beryl.so" ;;
  *) web="" ;;
esac
run_url="${web:+$web/projects/$INPUT_PROJECT/runs/$run_id}"
[ -n "$run_url" ] || echo "::warning title=Beryl::No web app is known for BERYL_API_URL, so run-url is empty."
{
  echo "run-id=$run_id"
  echo "run-url=$run_url"
} >>"${GITHUB_OUTPUT:-/dev/null}"
echo "Beryl run $run_id${run_url:+: $run_url}"

watch=(runs watch "$run_id" --workspace "$INPUT_WORKSPACE" --project "$INPUT_PROJECT")
[ -n "${INPUT_TIMEOUT:-}" ] && watch+=(--timeout "$INPUT_TIMEOUT")
"$beryl" "${watch[@]}"
