#!/usr/bin/env bash
# Commands that change cluster state must name the local kind context explicitly, so they can
# never hit whatever context kubectl happens to point at.
cmd=$(jq -r '.tool_input.command // empty')
ctx=kind-heimdall

if [[ "$cmd" =~ (^|[[:space:];&|])kubectl[[:space:]] ]] &&
  [[ "$cmd" =~ kubectl[[:space:]].*(apply|create|delete|edit|patch|replace|scale|exec|drain|cordon|label|annotate|rollout|set)([[:space:]]|$) ]] &&
  ! [[ "$cmd" =~ --context[=[:space:]]$ctx([[:space:]]|$) ]]; then
  echo "kubectl commands that change state must pass --context $ctx." >&2
  exit 2
fi

if [[ "$cmd" =~ (^|[[:space:];&|])helm[[:space:]]+(install|upgrade|uninstall|rollback|delete) ]] &&
  ! [[ "$cmd" =~ --kube-context[=[:space:]]$ctx([[:space:]]|$) ]]; then
  echo "helm commands that change state must pass --kube-context $ctx." >&2
  exit 2
fi
exit 0
