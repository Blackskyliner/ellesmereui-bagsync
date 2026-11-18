# Sourced by sim-test.sh and visual-test.sh after ADDONS is set: puts the
# addons under test into the simulator's Interface/AddOns and takes them out
# again. wow-sim loads an addon's font files only from inside its AddOns
# directory (a symlink there that leads outside does not count), so each addon
# is a mirror of hard links to its source files: no copy of the data, and
# every path stays inside the directory.
SIM_ADDON_NAMES=(EllesmereUIBags_Alts EllesmereUIBags_Alts_SimTests EllesmereUI EllesmereUIBags EllesmereUIBlizzardSkin)
# sim_addon <name> <source dir>: the addon <name> holds what <source dir>
# holds now.
sim_addon() {
  [ -n "$1" ] && [ -d "$2" ] || { echo "sim_addon: no addon $1 at $2" >&2; return 1; }
  [ -L "$ADDONS/$1" ] && rm "$ADDONS/$1"
  rsync -a --delete --link-dest="$2/" "$2/" "$ADDONS/$1/"
}
# sim_addon_drop <name>: takes one addon out.
sim_addon_drop() {
  if [ -L "$ADDONS/$1" ]; then rm "$ADDONS/$1"; elif [ -d "$ADDONS/$1" ]; then rm -rf "${ADDONS:?}/$1"; fi
}
sim_addons_clear() {
  local n
  for n in "${SIM_ADDON_NAMES[@]}"; do sim_addon_drop "$n"; done
}
