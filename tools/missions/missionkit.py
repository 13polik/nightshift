"""Mission kit: turns a compact mission description (rooms per band + objective chain +
texts in EN/PL) into the three things the game loads:

  data/facilities/<id>.json   facility layout (rooms, doors, devices, patrol routes)
  data/missions/<id>.tres     MissionData resource (objectives, events, enemies, loot)
  localization/{en,pl}.json   all texts (merged in place, existing keys updated)

Layout shape (tile grid, 1 tile = 2 m):

    [ north band rooms .................... ]
  W [ corridor A ........................... ] E
  Y [ middle band rooms (doors to A and B) . ] Y
  A [ corridor B ........................... ] A
  R [ south band rooms .................... ] R
  D                                            D

Two corridors joined by the middle rooms give the Hunter loops to chase players around;
the west yard is the insertion point, either yard can be the extraction.
"""
import json
import os

X0 = 12  # first tile column of the building (west yard occupies 2..11)


class Room:
    def __init__(self, rid, kind, w, en, pl, tags=(), loot=None, dev=(), door="normal",
                 lockdown=True, enemy=False, zone=None, link=False):
        self.id, self.kind, self.w, self.en, self.pl = rid, kind, w, en, pl
        self.tags = list(tags)
        self.loot = loot
        self.dev = list(dev)        # [(device_kind, tag)]
        self.door, self.lockdown, self.enemy, self.link = door, lockdown, enemy, link
        self.zone = zone or ("generator" if kind == "generator" else "main")


DEFAULT_LOOT = {
    "lobby": ["general"], "security": ["general", "keycard_spawn"], "office": ["general", "keycard_spawn", "research"],
    "storage": ["general", "component_spawn", "tools"], "medical": ["medical", "general"],
    "lab": ["general", "component_spawn", "research"], "maintenance": ["component_spawn", "tools"],
    "server": ["research", "general"], "generator": ["tools", "component_spawn"], "tunnel": ["tools"],
    "pump": ["tools", "general"], "hall": ["general"], "containment": ["research"],
    "control": ["general", "medical"], "archive": ["research", "medical"], "freezer": ["general", "component_spawn"],
}


def _key(*parts):
    return "_".join(str(p) for p in parts).upper()


class Mission:
    def __init__(self, mid, en, pl, desc_en, desc_pl, loc_en, loc_pl, **kw):
        self.id = mid
        self.texts = {"en": {}, "pl": {}}
        self.name_key = _key("MISSION", mid)
        self.desc_key = _key("MISSION", mid, "DESC")
        self.loc_key = _key("LOC", mid)
        self._t(self.name_key, en, pl)
        self._t(self.desc_key, desc_en, desc_pl)
        self._t(self.loc_key, loc_en, loc_pl)
        self.unlock = kw.get("unlock", 1)
        self.recommended = kw.get("recommended", self.unlock)
        self.minutes = kw.get("minutes", 15)
        self.threat = kw.get("threat", 0.04)
        self.powered = kw.get("powered", False)
        self.hunters = kw.get("hunters", 1)
        self.release = kw.get("release", 80.0)
        self.events = kw.get("events", ["power_failure", "lockdown", "alarm", "hunter_alert", "emergency_evacuation", "generator_noise"])
        self.extraction = kw.get("extraction", "east")  # east | west | both
        self.depths = kw.get("depths", (9, 7, 9))
        self.width = kw.get("width", 40)
        self.height = kw.get("height", 4.0)
        self.filler = kw.get("filler", ("storage", "storage", "storage"))
        self.loot_bias = kw.get("loot_bias", {})
        self.north, self.middle, self.south = [], [], []
        self.objectives, self.optional = [], []
        self.notes = []
        self.yard_names = kw.get("yards", (("Yard", "Plac"), ("Exit Yard", "Plac wyjściowy")))

    def _t(self, key, en, pl):
        self.texts["en"][key] = en
        self.texts["pl"][key] = pl

    # --- content builders ----------------------------------------------------------
    def note(self, en, pl):
        k = _key("NOTE", self.id, len(self.notes) + 1)
        self._t(k, en, pl)
        self.notes.append(k)

    def obj(self, oid, otype, title, hint, optional=False, **f):
        """title / hint = (en, pl). otype: reach|interact|collect|deliver|survive|extract"""
        tk = _key("OBJ", self.id, oid)
        self._t(tk, *title)
        self._t(tk + "_HINT", *hint)
        o = {"id": oid, "type": otype, "title_key": tk, "hint_key": tk + "_HINT"}
        o.update(f)
        (self.optional if optional else self.objectives).append(o)
        return o

    # --- layout ----------------------------------------------------------------------
    def build_layout(self):
        dn, dm, ds = self.depths
        W = self.width
        zA = 2 + dn
        zM = zA + 3
        zB = zM + dm
        zS = zB + 3
        H = zS - zA
        rooms, doors, spawns_enemy = [], [], []
        bands = {"north": (self.north, 2, dn), "middle": (self.middle, zM, dm), "south": (self.south, zS, ds)}
        placed = {}
        for bi, (band, (lst, z, d)) in enumerate(bands.items()):
            used = sum(r.w for r in lst)
            assert used <= W, "%s band of %s too wide (%d > %d)" % (band, self.id, used, W)
            items = list(lst)
            fill = W - used
            n_fill = 0
            while fill > 0:
                w = fill if fill <= 10 else min(8, fill - 4)
                if w < 4:  # merge tiny leftovers into the previous filler / last room
                    items[-1].w += fill
                    break
                n_fill += 1
                kind = self.filler[bi]
                items.append(Room("%s_extra_%d" % (band, n_fill), kind, w, *FILLER_NAMES.get(kind, ("Storage", "Magazyn")), lockdown=(n_fill % 2 == 0)))
                fill -= w
            x = X0
            for r in items:
                placed[r.id] = (r, band, x, z, d)
                x += r.w
        corr_a = {"id": "corridor_a", "name_key": _key("ROOM", self.id, "corridor_a"), "level": 0, "rect": [X0, zA, W, 3],
                  "kind": "corridor", "tags": ["corridor"], "power_zone": "main", "loot_tags": ["general"]}
        corr_b = dict(corr_a, id="corridor_b", name_key=_key("ROOM", self.id, "corridor_b"), rect=[X0, zB, W, 3])
        self._t(corr_a["name_key"], "North Corridor", "Korytarz północny")
        self._t(corr_b["name_key"], "South Corridor", "Korytarz południowy")
        rooms += [corr_a, corr_b]
        west_tags = ["insertion"] + (["extraction"] if self.extraction in ("west", "both") else [])
        east_tags = ["extraction"] if self.extraction in ("east", "both") else ["exit_yard"]
        yw = {"id": "yard_west", "name_key": _key("ROOM", self.id, "yard_west"), "level": 0, "rect": [2, zA, 10, H],
              "kind": "outdoor", "outdoor": True, "tags": west_tags, "power_zone": "exterior",
              "features": [{"type": "spawn_player", "pos": [5.0 + i * 1.5, zA + H / 2.0]} for i in range(4)] + [
                  {"type": "prop", "kind": "vehicle", "pos": [4.5, zA + H - 1.6], "face": "e"},
                  {"type": "prop", "kind": "barrier", "pos": [3.0, zA + 0.8]}] +
              ([{"type": "prop", "kind": "evac_beacon", "pos": [2.8, zA + 1.5]}] if "extraction" in west_tags else [])}
        ye = {"id": "yard_east", "name_key": _key("ROOM", self.id, "yard_east"), "level": 0, "rect": [X0 + W, zA, 8, H],
              "kind": "outdoor", "outdoor": True, "tags": east_tags, "power_zone": "exterior",
              "features": [{"type": "prop", "kind": "evac_beacon", "pos": [X0 + W + 6.5, zA + H / 2.0]},
                           {"type": "prop", "kind": "crate_stack", "pos": [X0 + W + 1.5, zA + H - 1.2]},
                           {"type": "prop", "kind": "barrel", "pos": [X0 + W + 6.0, zA + 0.8]}]}
        self._t(yw["name_key"], *self.yard_names[0])
        self._t(ye["name_key"], *self.yard_names[1])
        rooms += [yw, ye]
        for zc in (zA, zB):
            for dz in range(3):
                doors.append({"a": [X0 - 1, zc + dz], "b": [X0, zc + dz], "type": "open"})
                doors.append({"a": [X0 + W - 1, zc + dz], "b": [X0 + W, zc + dz], "type": "open"})
        prev = {"north": None, "middle": None, "south": None}
        for rid, (r, band, x, z, d) in placed.items():
            loot = r.loot if r.loot is not None else DEFAULT_LOOT.get(r.kind, ["general"])
            name_key = _key("ROOM", self.id, rid)
            self._t(name_key, r.en, r.pl)
            feats = []
            n = len(r.dev)
            for i, (dk, tag) in enumerate(r.dev):
                fx = x + (i + 1) * r.w / (n + 1)
                if band == "middle":
                    fz = z + (i + 1) * d / (n + 1)
                    feats.append({"type": "interactable", "kind": dk, "tag": tag, "pos": [x + 0.4, round(fz, 2)], "face": "e"})
                elif dk == "generator":
                    fz = z + 2.6 if band == "north" else z + d - 2.6
                    feats.append({"type": "interactable", "kind": dk, "tag": tag, "pos": [round(fx, 2), fz], "face": "s" if band == "north" else "n"})
                elif band == "north":
                    feats.append({"type": "interactable", "kind": dk, "tag": tag, "pos": [round(fx, 2), z + 0.4], "face": "s"})
                else:
                    feats.append({"type": "interactable", "kind": dk, "tag": tag, "pos": [round(fx, 2), z + d - 0.4], "face": "n"})
            if r.enemy:
                feats.append({"type": "enemy_spawn", "pos": [x + r.w / 2.0, z + d / 2.0]})
                spawns_enemy.append(rid)
            rooms.append({"id": rid, "name_key": name_key, "level": 0, "rect": [x, z, r.w, d], "kind": r.kind,
                          "tags": r.tags, "power_zone": r.zone, "loot_tags": loot, "features": feats})
            dx = x + r.w // 2
            dd = {"type": r.door}
            if r.lockdown:
                dd["lockdown"] = True
            if band == "north":
                doors.append(dict(dd, id="door_%s" % rid, a=[dx, z + d - 1], b=[dx, zA]))
            elif band == "south":
                doors.append(dict(dd, id="door_%s" % rid, a=[dx, z], b=[dx, zB + 2]))
            else:
                doors.append(dict(dd, id="door_%s_n" % rid, a=[x + 1, z], b=[x + 1, zA + 2]))
                doors.append({"id": "door_%s_s" % rid, "type": "normal", "a": [x + r.w - 2, z + d - 1], "b": [x + r.w - 2, zB]})
            p = prev[band]
            if p is not None and p[0].link:
                doors.append({"id": "door_%s_%s" % (p[0].id, rid), "type": "normal", "lockable": True,
                              "a": [x - 1, z + d // 2], "b": [x, z + d // 2]})
            prev[band] = (r, x)
        assert spawns_enemy, "%s needs an enemy spawn room" % self.id
        # patrol routes (tile coordinates)
        routes = []
        for band, zc in (("north", zA + 1.5), ("south", zB + 1.5)):
            pts = [[X0 + 1.0, zc]]
            for rid, (r, b, x, z, d) in placed.items():
                if b == band:
                    pts += [[x + r.w // 2 + 0.5, zc], [x + r.w / 2.0, z + d / 2.0], [x + r.w // 2 + 0.5, zc]]
            pts.append([X0 + W - 1.0, zc])
            routes.append({"id": "%s_sweep" % band, "level": 0, "points": pts})
        loop = []
        for rid, (r, b, x, z, d) in placed.items():
            if b == "middle":
                loop += [[x + 1.5, zA + 1.5], [x + r.w / 2.0, z + d / 2.0], [x + r.w - 1.5, zB + 1.5]]
        loop += [[X0 + W - 2.0, zB + 1.5], [X0 + 2.0, zB + 1.5], [X0 + 2.0, zA + 1.5]]
        routes.append({"id": "middle_loop", "level": 0, "points": loop})
        return {"id": self.id, "name_key": self.loc_key, "notes": self.notes, "tile_size": 2.0,
                "levels": {"0": {"y": 0.0, "height": self.height}},
                "rooms": rooms, "doors": doors, "route_locks": {}, "patrol_routes": routes}

    # --- MissionData .tres --------------------------------------------------------------
    def build_tres(self):
        ext = [("Script", "res://scripts/data/enemy_data.gd", "enemy_s"), ("Resource", "res://data/enemies/hunter.tres", "hunter"),
               ("Script", "res://scripts/data/event_data.gd", "event_s")]
        for e in self.events:
            ext.append(("Resource", "res://data/events/%s.tres" % e, "ev_" + e))
        ext += [("Script", "res://scripts/data/loot_table.gd", "loot_s"), ("Script", "res://scripts/data/objective_data.gd", "obj_s"),
                ("Script", "res://scripts/data/reward_data.gd", "rew_s"), ("Script", "res://scripts/data/mission_data.gd", "mis_s")]
        out = ['[gd_resource type="Resource" script_class="MissionData" format=3]', ""]
        for t, path, i in ext:
            out.append('[ext_resource type="%s" path="%s" id="%s"]' % (t, path, i))
        out.append("")
        weights = {"access_decoder": 0.4, "arc_cell": 1.0, "arc_emitter": 0.4, "bandage": 3.0, "battery": 3.0, "crowbar": 0.6, "medkit": 1.0}
        weights.update(self.loot_bias)
        out += ['[sub_resource type="Resource" id="loot"]', 'script = ExtResource("loot_s")', "weights = " + _gd_dict(weights),
                'guaranteed = {\n"arc_emitter": 1,\n"battery": 2,\n"crowbar": 1\n}', "fill_ratio = 0.4", "container_fill_ratio = 0.55", ""]
        types = {"reach": 0, "interact": 1, "collect": 2, "deliver": 3, "survive": 4, "extract": 5}
        ids = []
        for o in self.objectives + self.optional:
            sid = "o_" + o["id"]
            ids.append(sid)
            out += ['[sub_resource type="Resource" id="%s"]' % sid, 'script = ExtResource("obj_s")', 'id = &"%s"' % o["id"],
                    'title_key = "%s"' % o["title_key"], 'hint_key = "%s"' % o["hint_key"]]
            if types[o["type"]]:
                out.append("type = %d" % types[o["type"]])
            for k, v in o.items():
                if k in ("id", "type", "title_key", "hint_key"):
                    continue
                out.append("%s = %s" % (k, _gd_value(k, v)))
            if o in self.optional:
                out.append("optional = true")
            out.append("")
        out += ['[sub_resource type="Resource" id="rewards"]', 'script = ExtResource("rew_s")', ""]
        main = ", ".join('SubResource("o_%s")' % o["id"] for o in self.objectives)
        opt = ", ".join('SubResource("o_%s")' % o["id"] for o in self.optional)
        evs = ", ".join('ExtResource("ev_%s")' % e for e in self.events)
        hunters = ", ".join(['ExtResource("hunter")'] * self.hunters)
        out += ["[resource]", 'script = ExtResource("mis_s")', 'id = &"%s"' % self.id, 'name_key = "%s"' % self.name_key,
                'description_key = "%s"' % self.desc_key, 'location_key = "%s"' % self.loc_key,
                'layout_path = "res://data/facilities/%s.json"' % self.id,
                'objectives = Array[ExtResource("obj_s")]([%s])' % main,
                'optional_objectives = Array[ExtResource("obj_s")]([%s])' % opt,
                'events = Array[ExtResource("event_s")]([%s])' % evs,
                'loot_table = SubResource("loot")', 'rewards = SubResource("rewards")',
                'enemies = Array[ExtResource("enemy_s")]([%s])' % hunters,
                "enemy_release_time = %.1f" % self.release, "recommended_level = %d" % self.recommended,
                "unlock_level = %d" % self.unlock, "threat_per_minute = %.3f" % self.threat,
                "target_duration_minutes = %.1f" % self.minutes]
        if self.powered:
            out.append("start_powered = true")
        return "\n".join(out) + "\n"

    def write(self, root):
        layout = self.build_layout()
        with open(os.path.join(root, "data/facilities/%s.json" % self.id), "w", encoding="utf-8", newline="\n") as f:
            json.dump(layout, f, ensure_ascii=False, indent="\t")
            f.write("\n")
        with open(os.path.join(root, "data/missions/%s.tres" % self.id), "w", encoding="utf-8", newline="\n") as f:
            f.write(self.build_tres())


FILLER_NAMES = {
    "storage": ("Storage", "Magazyn"), "office": ("Office", "Biuro"), "maintenance": ("Workshop", "Warsztat"),
    "hall": ("Hall", "Hala"), "archive": ("Archive", "Archiwum"), "tunnel": ("Service Tunnel", "Tunel serwisowy"),
    "medical": ("Treatment Room", "Gabinet zabiegowy"), "lab": ("Laboratory", "Laboratorium"), "pump": ("Pump Room", "Pompownia"),
    "control": ("Monitoring", "Monitoring"), "freezer": ("Cold Room", "Chłodnia"), "server": ("Server Room", "Serwerownia"),
    "security": ("Guard Room", "Wartownia"), "lobby": ("Waiting Room", "Poczekalnia"), "containment": ("Holding Cells", "Cele"),
}


def _gd_value(key, v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (list, tuple)):
        return "PackedStringArray(%s)" % ", ".join('"%s"' % x for x in v)
    if isinstance(v, float):
        return "%.2f" % v
    if isinstance(v, int):
        return str(v)
    if key in ("target_tag", "spawn_items_tag", "sets_flag", "unlock_tag", "grants_item"):
        return '&"%s"' % v
    return '"%s"' % v


def _gd_dict(d):
    return "{\n" + ",\n".join('"%s": %s' % (k, float(v)) for k, v in d.items()) + "\n}"


def merge_localization(root, missions):
    for lang in ("en", "pl"):
        p = os.path.join(root, "localization/%s.json" % lang)
        with open(p, encoding="utf-8") as f:
            d = json.load(f)
        for m in missions:
            d.update(m.texts[lang])
        with open(p, "w", encoding="utf-8", newline="\n") as f:
            json.dump(d, f, ensure_ascii=False, indent="\t")
            f.write("\n")
