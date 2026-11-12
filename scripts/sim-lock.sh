# Sourced by sim-test.sh and visual-test.sh: one simulator run at a time.
# Git worktrees share .tools (a symlink to the main checkout's), and with it
# the simulator's Interface/AddOns, where each run links the addons under test
# and unlinks them on exit, and .tools/visual-out. Parallel runs from two
# checkouts would test each other's code. The lock is a directory (mkdir is
# atomic) holding the owner's PID; a lock whose owner is gone is taken over.
SIM_LOCK="$ROOT/.tools/.sim-lock"
sim_lock_acquire() {
  local waited=0 owner
  until mkdir "$SIM_LOCK" 2>/dev/null; do
    owner="$(cat "$SIM_LOCK/pid" 2>/dev/null || true)"
    if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
      rm -rf "$SIM_LOCK"
      continue
    fi
    if [ "$waited" = 0 ]; then echo "waiting for another simulator run (pid ${owner:-?})" >&2; fi
    waited=1
    sleep 1
  done
  echo $$ > "$SIM_LOCK/pid"
}
sim_lock_release() {
  if [ "$(cat "$SIM_LOCK/pid" 2>/dev/null)" = "$$" ]; then rm -rf "$SIM_LOCK"; fi
}
