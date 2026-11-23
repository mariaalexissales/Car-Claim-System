# Car Claim System

A Project Zomboid (Build 42) multiplayer mod. Claim a vehicle, then decide who may ride in it, drive it, open its storage, work on it or tow it.

- Right-click a vehicle and open **Vehicle Claim**. Claiming needs the vehicle's key (or a hotwire) and you standing next to it.
- Grant flags to **My Faction**, **My Safehouse**, or one player picked from **Nearby Players** or **Online Players**. The five flags are independent: Passenger, Drive, Storage, Mechanics, Tow.
- Faction and safehouse grants follow live membership. A player's own entry overrides the groups.
- **View Permissions** lists everyone with access in one table.
- **Claimed Vehicles**, on any right-click, lists every vehicle you have claimed: what it is, the tile it was last seen on, how far that is from you and how long ago the server last had it loaded.
- **Transfer Ownership** sends an offer the other player has to accept. The permission list is wiped on transfer.
- Admins pass every check and can release or reassign a claim.
- Any vehicle left running with nobody in the driver's seat is switched off after a while.

Sandbox options: claims per player (default 3), claim expiry in real days (default 30), idle engine shut-off in real minutes (default 10). 0 turns each one off.

## Checks

Run from this folder:

```
python ../estral-tools/car-claim-system/check_lua.py
python ../estral-tools/car-claim-system/check_runtime.py
python ../estral-tools/car-claim-system/check_translations.py
python ../estral-tools/car-claim-system/harness/run_tests.py
```
