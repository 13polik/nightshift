"""Generates missions 3-15 of NIGHT SHIFT (layouts, MissionData, EN/PL texts).
Missions 1 (power_restoration) and 2 (signal_lost) are hand-authored.

    python tools/missions/gen_missions.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from missionkit import Mission, Room, merge_localization  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ALL = []


def mission(*a, **kw):
    m = Mission(*a, **kw)
    ALL.append(m)
    return m


# --- shared objective helpers ---------------------------------------------------------------

def reach(m, oid, tag, title, hint, xp=40):
    m.obj(oid, "reach", title, hint, target_tag=tag, threat_on_complete=0.02, reward_xp=xp)


def power_up(m, generator=True, hint_gen=None, hint_power=None):
    if generator:
        m.obj("generator", "interact", ("Start the backup generator", "Uruchom generator awaryjny"),
              hint_gen or ("The generator room is marked on the wall plan. It will be loud.", "Maszynownia jest na planie budynku. Będzie głośno."),
              target_tag="generator", duration=4.0, sets_flag="power_generator", events_on_complete=["generator_noise"],
              threat_on_complete=0.08, work_noise=16.0, reward_xp=80)
    m.obj("power", "interact", ("Restore main power", "Przywróć główne zasilanie"),
          hint_power or ("Throw the main breaker next to the generator.", "Przełącz główny wyłącznik obok generatora."),
          target_tag="power_breaker", duration=2.0, sets_flag="power_main", threat_on_complete=0.06, reward_xp=70)


def interact(m, oid, tag, title, hint, dur=6.0, noise=4.0, xp=90, **kw):
    m.obj(oid, "interact", title, hint, target_tag=tag, duration=dur, work_noise=noise, reward_xp=xp, **kw)


def parts(m, oid, title, hint, pick=2, pool=("fuse", "circuit_board", "capacitor"), xp=80):
    m.obj(oid, "collect", title, hint, item_pool=list(pool), pick_items=pick, spawn_items_tag="component_spawn", reward_xp=xp)


def deliver(m, oid, tag, src, title, hint, dur=6.0, noise=12.0, xp=100, **kw):
    m.obj(oid, "deliver", title, hint, target_tag=tag, item_pool=["@" + src], duration=dur, work_noise=noise,
          threat_on_complete=0.08, reward_xp=xp, **kw)


def collect(m, oid, item, count, spawn_tag, title, hint, reveal=False, xp=80, spare=1, optional=False, **kw):
    m.obj(oid, "collect", title, hint, optional=optional, item_pool=[item], required_count=count, spawn_items_tag=spawn_tag,
          spare_items=spare, reveal_item_location=reveal, reward_xp=xp, **kw)


def carry(m, oid, item, title, hint, xp=40):
    m.obj(oid, "collect", title, hint, item_pool=[item], reward_xp=xp)


def finale(m, tag, title, hint, survive=70, survive_text=None, extract_text=None, dur=4.0):
    m.obj("call_evac", "interact", title, hint, target_tag=tag, duration=dur, events_on_complete=["emergency_evacuation"],
          threat_on_complete=0.06, work_noise=6.0, reward_xp=80)
    st = survive_text or (("Hold out until extraction arrives", "Przetrwaj do przybycia ewakuacji"),
                          ("Stay together. Stay alive.", "Trzymajcie się razem. Przeżyjcie."))
    m.obj("survive", "survive", st[0], st[1], duration=float(survive), reward_xp=120)
    et = extract_text or (("Get to the extraction point", "Dotrzyj do punktu ewakuacji"),
                          ("Extraction won't wait. Move!", "Ewakuacja nie będzie czekać. Ruszaj!"))
    m.obj("extract", "extract", et[0], et[1], target_tag="extraction", duration=90.0, reward_xp=0)


def opt_server(m, tag, title, hint):
    m.obj("opt_server", "interact", title, hint, optional=True, target_tag=tag, duration=8.0, work_noise=4.0, reward_xp=100, reward_currency=25)


def opt_drives(m, title, hint, count=2):
    collect(m, "opt_drives", "data_drive", count, "research", title, hint, xp=120, optional=True, reward_currency=30)


GEN_ROOM = lambda rid="generator_room", en="Generator Room", pl="Maszynownia", enemy=False: Room(
    rid, "generator", 10, en, pl, dev=[("generator", "generator"), ("breaker", "power_breaker")], enemy=enemy)


# =============================================================================================
# 3. WARD NINE - hospital
m = mission("ward_nine", "Ward Nine", "Oddział Dziewiąty",
            "St. Agnes took the first patients from Kessler. Ward Nine stopped reporting at midnight. Find patient zero's file, recover the isolation sample and get out through the ambulance bay.",
            "Szpital św. Agnieszki przyjął pierwszych pacjentów z Kesslera. Oddział Dziewiąty zamilkł o północy. Znajdź kartę pacjenta zero, zabezpiecz próbkę z izolatki i uciekaj przez podjazd karetek.",
            "St. Agnes Hospital", "Szpital św. Agnieszki", unlock=2, minutes=14, powered=True, extraction="east",
            yards=(("Hospital Car Park", "Parking szpitala"), ("Ambulance Bay", "Podjazd karetek")),
            filler=("medical", "office", "storage"), loot_bias={"medkit": 2.0, "bandage": 4.0})
m.north = [Room("reception", "lobby", 8, "Reception", "Rejestracja"),
           Room("ward_a", "medical", 10, "Ward 9A", "Sala 9A", link=True),
           Room("pharmacy", "storage", 7, "Pharmacy", "Apteka", loot=["medical", "component_spawn"]),
           Room("isolation", "containment", 10, "Isolation Ward", "Izolatka", dev=[("containment_console", "isolation_console")], door="secure", enemy=True)]
m.middle = [Room("nurses", "security", 8, "Nurses' Station", "Dyżurka pielęgniarek", tags=["nurses_station"], dev=[("terminal", "records_terminal"), ("alarm_panel", "alarm_panel")]),
            Room("surgery", "medical", 10, "Surgery", "Sala operacyjna"),
            Room("records", "archive", 8, "Medical Records", "Archiwum medyczne", dev=[("terminal", "records_terminal")]),
            Room("ward_b", "medical", 10, "Ward 9B", "Sala 9B", enemy=True)]
m.south = [GEN_ROOM("generator_room", "Hospital Plant Room", "Kotłownia szpitala"),
           Room("morgue", "freezer", 10, "Morgue", "Kostnica", enemy=True),
           Room("laundry", "storage", 8, "Laundry", "Pralnia"),
           Room("chapel", "office", 8, "Chaplain's Office", "Kaplica", dev=[("evac_console", "ambulance_radio")])]
reach(m, "reach_nurses", "nurses_station", ("Reach the nurses' station", "Dotrzyj do dyżurki pielęgniarek"),
      ("Ward Nine is on the ground floor. Follow the north corridor.", "Oddział Dziewiąty jest na parterze. Idź północnym korytarzem."))
interact(m, "patient_file", "records_terminal", ("Find patient zero's file", "Znajdź kartę pacjenta zero"),
         ("Search the records terminals. One of them still has the file.", "Przeszukaj terminale z dokumentacją. Jeden z nich wciąż ma kartę."),
         dur=6.0, events_on_complete=["power_failure"], xp=100)
m.obj("power", "interact", ("Bring the power back", "Przywróć zasilanie"),
      ("The hospital just went dark. The main breaker is in the plant room.", "Szpital właśnie zgasł. Główny wyłącznik jest w kotłowni."),
      target_tag="power_breaker", duration=2.0, sets_flag="power_main", threat_on_complete=0.06, reward_xp=70)
collect(m, "isolation_key", "keycard", 1, "keycard_spawn", ("Find the isolation keycard", "Znajdź kartę do izolatki"),
        ("The file says the head nurse carried it. Check the offices.", "W karcie jest napisane, że miała ją oddziałowa. Sprawdź biura."), reveal=True, spare=0)
interact(m, "isolation", "isolation_console", ("Unseal the isolation ward", "Otwórz izolatkę"),
         ("Hold the isolation console. It will hear the seals release.", "Trzymaj konsolę izolatki. Usłyszy otwierane śluzy."),
         dur=8.0, noise=12.0, events_on_start=["hunter_alert"], grants_item="sample_case", xp=150, threat_on_complete=0.1)
carry(m, "secure_sample", "sample_case", ("Take the isolation sample", "Zabierz próbkę z izolatki"),
      ("Whoever carries the case is slower and louder. Cover them.", "Kto niesie walizkę, jest wolniejszy i głośniejszy. Osłaniajcie go."))
finale(m, "ambulance_radio", ("Radio the ambulance", "Wezwij karetkę przez radio"),
       ("The chaplain's office has the emergency radio.", "Radio awaryjne jest w kaplicy."), survive=65,
       extract_text=(("Get to the ambulance bay", "Dotrzyj do podjazdu karetek"), ("East side of the hospital. Go!", "Wschodnia strona szpitala. Biegiem!")))
opt_drives(m, ("Recover the trial data", "Odzyskaj dane z badań"), ("Two drives with the clinical trial data are hidden in the wards.", "Na oddziałach są ukryte dwa dyski z danymi z badań klinicznych."))
m.note("CHART, BED 4: Transferred from Kessler 21:30. Temp 34.1. Does not blink. Restrained at 23:00 after biting orderly.",
       "KARTA, ŁÓŻKO 4: Przeniesiony z Kesslera 21:30. Temp. 34,1. Nie mruga. Unieruchomiony o 23:00 po ugryzieniu sanitariusza.")
m.note("Night nurse: the isolation door was locked from the INSIDE. I have the only key. I'm not opening it.",
       "Nocna pielęgniarka: drzwi izolatki zamknięto OD ŚRODKA. Mam jedyny klucz. Nie otworzę ich.")
m.note("Morgue log: drawer 7 was empty at 01:00. Drawer 7 was full at 00:30.",
       "Dziennik kostnicy: szuflada 7 była pusta o 01:00. O 00:30 była pełna.")

# =============================================================================================
# 4. LAST TRAIN - metro
m = mission("last_train", "Last Train", "Ostatni pociąg",
            "Westgate station on Line 4 is the last way out of the city centre. Restore the substation, repair the signal relay and call the last train before the tunnels fill with what came up from below.",
            "Stacja Zachodnia na linii 4 to ostatnia droga ze śródmieścia. Uruchom podstację, napraw przekaźnik sygnalizacji i wezwij ostatni pociąg, zanim tunele wypełni to, co wyszło z dołu.",
            "Westgate Station, Line 4", "Stacja Zachodnia, linia 4", unlock=2, minutes=15, extraction="east", height=4.4,
            depths=(9, 7, 8), filler=("tunnel", "hall", "storage"),
            yards=(("Street Entrance", "Wejście z ulicy"), ("Tunnel Mouth", "Wylot tunelu")))
m.north = [Room("ticket_hall", "hall", 12, "Ticket Hall", "Hala kasowa", tags=["ticket_hall"]),
           Room("ticket_office", "office", 7, "Ticket Office", "Kasy biletowe", dev=[("terminal", "server_terminal")]),
           Room("substation", "generator", 10, "Substation", "Podstacja", dev=[("generator", "generator"), ("breaker", "power_breaker")]),
           Room("tunnel_n", "tunnel", 11, "Northbound Tunnel", "Tunel północny", enemy=True, door="heavy")]
m.middle = [Room("platform_1", "hall", 14, "Platform 1", "Peron 1", tags=["platform"]),
            Room("signal_room", "maintenance", 8, "Signal Room", "Nastawnia", dev=[("electrical_panel", "signal_relay")]),
            Room("platform_2", "hall", 12, "Platform 2", "Peron 2", dev=[("electrical_panel", "signal_relay")])]
m.south = [Room("control", "control", 10, "Line Control", "Dyspozytornia", dev=[("terminal", "dispatch_terminal"), ("alarm_panel", "alarm_panel")]),
           Room("depot", "storage", 10, "Maintenance Depot", "Zajezdnia techniczna"),
           Room("drainage", "pump", 9, "Drainage Pumps", "Pompy odwadniające", enemy=True),
           Room("tunnel_s", "tunnel", 11, "Southbound Tunnel", "Tunel południowy", enemy=True, door="heavy")]
reach(m, "reach_platform", "platform", ("Get down to the platforms", "Zejdź na perony"),
      ("Through the ticket hall and down to the platforms.", "Przez halę kasową i w dół na perony."))
power_up(m, hint_gen=("The substation is north of the main corridor.", "Podstacja jest na północ od głównego korytarza."))
parts(m, "relay_parts", ("Find parts for the signal relay", "Znajdź części do przekaźnika"),
      ("Burned-out parts are listed on the relay cabinet. Search the depot and workshops.", "Spalone części są wypisane na szafie przekaźnika. Przeszukaj zajezdnię i warsztaty."))
deliver(m, "repair_relay", "signal_relay", "relay_parts", ("Repair the signal relay", "Napraw przekaźnik sygnalizacji"),
        ("Without signals the driver won't enter the station.", "Bez sygnalizacji maszynista nie wjedzie na stację."))
finale(m, "dispatch_terminal", ("Call the last train", "Wezwij ostatni pociąg"),
       ("Line control can still reach the driver.", "Dyspozytornia wciąż ma łączność z maszynistą."), survive=75, dur=8.0,
       survive_text=(("Hold the platform until the train arrives", "Utrzymaj peron do przyjazdu pociągu"), ("You can hear it in the tunnel. Not the train.", "Słychać coś w tunelu. To nie pociąg.")),
       extract_text=(("Board at the tunnel mouth", "Wsiadaj przy wylocie tunelu"), ("The train stops past the east platform. Run.", "Pociąg zatrzyma się za wschodnim peronem. Biegnij.")))
opt_server(m, "server_terminal", ("Download the CCTV archive", "Pobierz archiwum monitoringu"), ("The ticket office keeps the last hours of camera footage.", "Kasy trzymają nagrania z ostatnich godzin."))
m.note("Driver's radio, 00:12: Something on the track at km 3. It stood up. Not stopping again.", "Radio maszynisty, 00:12: Coś na torze na 3. kilometrze. Wstało. Więcej się nie zatrzymuję.")
m.note("Station notice: Line 4 suspended until further notice. Do not enter the tunnels for any reason.", "Komunikat: linia 4 zawieszona do odwołania. Pod żadnym pozorem nie wchodzić do tuneli.")
m.note("Cleaner's note: the drainage pumps keep clogging with something warm. Not rats. Too big for rats.", "Kartka sprzątacza: pompy odwadniające ciągle zapycha coś ciepłego. Nie szczury. Za duże na szczury.")

# =============================================================================================
# 5. OVERLOAD - power plant
m = mission("overload", "Overload", "Przeciążenie",
            "The Halvard plant feeds half the region and its control rods are drifting. Open the coolant valves, rebuild the turbine controller and stabilise the core - with something in the turbine hall that likes the heat.",
            "Elektrownia Halvard zasila pół regionu, a jej pręty kontrolne dryfują. Otwórz zawory chłodziwa, odbuduj sterownik turbiny i ustabilizuj rdzeń - a w hali turbin czai się coś, co lubi ciepło.",
            "Halvard Power Plant", "Elektrownia Halvard", unlock=3, minutes=16, threat=0.045, extraction="both", height=4.8,
            depths=(10, 7, 9), filler=("maintenance", "hall", "storage"),
            yards=(("Plant Gate", "Brama elektrowni"), ("Cooling Tower Yard", "Plac chłodni kominowych")))
m.north = [Room("control_room", "control", 10, "Main Control Room", "Główna sterownia", tags=["control_room"], dev=[("terminal", "core_console"), ("alarm_panel", "alarm_panel")]),
           Room("turbine_hall", "hall", 16, "Turbine Hall", "Hala turbin", dev=[("electrical_panel", "turbine_panel")], enemy=True, door="heavy"),
           Room("backup_gen", "generator", 10, "Backup Generators", "Generatory awaryjne", dev=[("generator", "generator"), ("breaker", "power_breaker")])]
m.middle = [Room("coolant_a", "pump", 10, "Coolant Pumps A", "Pompy chłodziwa A", dev=[("electrical_panel", "coolant_valve")]),
            Room("switchgear", "maintenance", 8, "Switchgear", "Rozdzielnia"),
            Room("coolant_b", "pump", 10, "Coolant Pumps B", "Pompy chłodziwa B", dev=[("electrical_panel", "coolant_valve")], enemy=True)]
m.south = [Room("workshop", "maintenance", 10, "Workshop", "Warsztat"),
           Room("stores", "storage", 10, "Parts Stores", "Magazyn części"),
           Room("server", "server", 8, "Plant Servers", "Serwerownia", dev=[("terminal", "server_terminal")]),
           Room("security", "security", 8, "Security", "Ochrona", dev=[("evac_console", "plant_radio")])]
reach(m, "reach_control", "control_room", ("Reach the main control room", "Dotrzyj do głównej sterowni"), ("North-west corner of the plant.", "Północno-zachodni róg elektrowni."))
power_up(m)
interact(m, "coolant", "coolant_valve", ("Open the coolant valves", "Otwórz zawory chłodziwa"),
         ("One of the pump rooms still has a working valve panel.", "W jednej z pompowni działa jeszcze panel zaworów."), dur=6.0, noise=10.0, xp=90)
parts(m, "controller_parts", ("Find parts for the turbine controller", "Znajdź części do sterownika turbiny"),
      ("The stores and the workshop should have spares.", "Magazyn i warsztat powinny mieć części zamienne."))
deliver(m, "rebuild_controller", "turbine_panel", "controller_parts", ("Rebuild the turbine controller", "Odbuduj sterownik turbiny"),
        ("The turbine hall is loud and open. Watch the dark between the turbines.", "Hala turbin jest głośna i otwarta. Uważaj na ciemność między turbinami."), dur=8.0, noise=14.0)
interact(m, "stabilise", "core_console", ("Stabilise the core", "Ustabilizuj rdzeń"),
         ("Hold the core console until the rods settle.", "Trzymaj konsolę rdzenia, aż pręty się ustabilizują."), dur=10.0, noise=12.0, events_on_start=["hunter_alert"], xp=150, threat_on_complete=0.1)
finale(m, "plant_radio", ("Call the evacuation", "Wezwij ewakuację"), ("The security radio reaches the fire brigade.", "Radio ochrony łączy ze strażą."), survive=70)
opt_server(m, "server_terminal", ("Copy the incident logs", "Skopiuj dziennik incydentów"), ("Someone ordered the plant to keep running. Find out who.", "Ktoś kazał utrzymać elektrownię w ruchu. Dowiedz się kto."))
m.note("Shift report: Turbine 2 vibrating at 3x tolerance. Maintenance says it's not mechanical. Maintenance went to look.", "Raport zmiany: turbina 2 wibruje 3x ponad normę. Utrzymanie ruchu mówi, że to nie mechanika. Poszli sprawdzić.")
m.note("Coolant line B temperature drop of 12 degrees at 02:10. Like something is drinking from it.", "Linia chłodziwa B: spadek temperatury o 12 stopni o 02:10. Jakby coś z niej piło.")
m.note("ORDER FROM KESSLER LIAISON: Plant stays online. No evacuation. No press. - signature illegible", "POLECENIE ŁĄCZNIKA KESSLERA: Elektrownia pracuje dalej. Bez ewakuacji. Bez prasy. - podpis nieczytelny")

# =============================================================================================
# 6. DEEP ARCHIVE - national archive heist
m = mission("deep_archive", "Deep Archive", "Głębokie archiwum",
            "Kessler stored its founding research in the Meridian National Archive. Disable the lockdown, decrypt the vault index and pull three drives out of the stacks before the archive seals itself for good.",
            "Kessler zdeponował swoje pierwsze badania w Archiwum Narodowym Meridian. Wyłącz blokadę, odszyfruj indeks skarbca i wynieś trzy dyski spomiędzy regałów, zanim archiwum zamknie się na dobre.",
            "Meridian National Archive", "Archiwum Narodowe Meridian", unlock=3, minutes=14, powered=True, extraction="west",
            depths=(10, 8, 9), filler=("archive", "office", "archive"),
            yards=(("Archive Forecourt", "Dziedziniec archiwum"), ("Loading Dock", "Rampa dostaw")),
            loot_bias={"access_decoder": 1.0})
m.north = [Room("reading_room", "archive", 12, "Reading Room", "Czytelnia"),
           Room("stacks_a", "archive", 12, "Stacks A", "Magazyn A", enemy=True, link=True),
           Room("stacks_b", "archive", 12, "Stacks B", "Magazyn B", loot=["research", "general"])]
m.middle = [Room("security", "security", 8, "Security Office", "Biuro ochrony", tags=["archive_security"], dev=[("terminal", "lockdown_terminal"), ("alarm_panel", "alarm_panel")]),
            Room("catalogue", "office", 10, "Catalogue", "Katalog", loot=["general", "keycard_spawn"]),
            Room("vault", "server", 10, "Vault Index", "Indeks skarbca", dev=[("terminal", "vault_terminal")], door="secure"),
            Room("restoration", "lab", 8, "Restoration Lab", "Pracownia konserwacji", dev=[("terminal", "server_terminal")])]
m.south = [Room("plant", "generator", 10, "Plant Room", "Kotłownia", dev=[("generator", "generator"), ("breaker", "power_breaker")]),
           Room("deep_stacks", "archive", 14, "Deep Stacks", "Głębokie regały", enemy=True, loot=["research", "medical"]),
           Room("offices", "office", 8, "Archivists' Offices", "Biura archiwistów", dev=[("evac_console", "dock_phone")])]
reach(m, "reach_security", "archive_security", ("Find the security office", "Znajdź biuro ochrony"), ("It's off the north corridor.", "Jest przy północnym korytarzu."))
interact(m, "lockdown", "lockdown_terminal", ("Disable the archive lockdown", "Wyłącz blokadę archiwum"),
         ("Overriding it will trip the alarm. Be ready.", "Obejście włączy alarm. Bądź gotowy."), dur=6.0, events_on_complete=["alarm"], xp=90)
collect(m, "vault_key", "keycard", 1, "keycard_spawn", ("Find the vault keycard", "Znajdź kartę do skarbca"),
        ("The security terminal shows where it was last swiped.", "Terminal ochrony pokazuje, gdzie użyto jej ostatnio."), reveal=True, spare=0)
interact(m, "decrypt", "vault_terminal", ("Decrypt the vault index", "Odszyfruj indeks skarbca"),
         ("The index tells you which shelves hide the Kessler drives.", "Indeks powie, na których półkach są dyski Kesslera."), dur=10.0, noise=6.0, events_on_start=["hunter_alert"], xp=130)
collect(m, "kessler_files", "data_drive", 3, "research", ("Recover the Kessler founding files", "Odzyskaj założycielskie akta Kesslera"),
        ("Three drives, marked on your map.", "Trzy dyski, zaznaczone na mapie."), reveal=True, xp=150)
finale(m, "dock_phone", ("Call the pickup", "Wezwij transport"), ("The archivists' offices still have a landline.", "W biurach archiwistów działa jeszcze telefon."), survive=60,
       extract_text=(("Get back to the forecourt", "Wróć na dziedziniec"), ("The van is waiting where you came in.", "Furgonetka czeka tam, gdzie weszliście.")))
opt_server(m, "server_terminal", ("Wipe the security footage", "Usuń nagrania z monitoringu"), ("Nobody needs to know you were here.", "Nikt nie musi wiedzieć, że tu byliście."))
m.note("Deposit slip 1987: Kessler Foundation, 14 boxes, 'Subject H - origin'. Access: director only.", "Kwit depozytowy 1987: Fundacja Kesslera, 14 pudeł, 'Obiekt H - pochodzenie'. Dostęp: tylko dyrektor.")
m.note("The stacks are colder near box 9. I keep hearing pages turning when nobody is there.", "Przy pudle 9 w magazynie jest zimniej. Ciągle słyszę przewracane kartki, choć nikogo nie ma.")
m.note("Lockdown protocol: if the vault is breached, all doors seal for 72 hours. Staff inside are on their own.", "Protokół blokady: przy włamaniu do skarbca wszystkie drzwi zamykają się na 72 godziny. Personel w środku zostaje sam.")

# =============================================================================================
# 7. QUARANTINE ZONE - biolab
m = mission("quarantine", "Quarantine Zone", "Strefa kwarantanny",
            "Sector 7 grew the cultures that made THE HUNTER. The containment field is failing. Repair it, extract a live culture and get through decontamination before the sector is burned.",
            "W sektorze 7 hodowano kultury, z których powstał ŁOWCA. Pole izolacyjne słabnie. Napraw je, wydobądź żywą kulturę i przejdź przez dekontaminację, zanim sektor zostanie spalony.",
            "Biolab Sector 7", "Biolaboratorium, sektor 7", unlock=4, minutes=16, threat=0.045, hunters=2, release=95.0, extraction="east",
            filler=("lab", "lab", "storage"),
            yards=(("Decon Tent", "Namiot dekontaminacji"), ("Burn Line", "Linia spalania")))
m.north = [Room("decon", "security", 8, "Decontamination", "Dekontaminacja", tags=["decon"], dev=[("alarm_panel", "alarm_panel")]),
           Room("lab_1", "lab", 10, "Culture Lab 1", "Laboratorium kultur 1", dev=[("terminal", "culture_terminal")], link=True),
           Room("lab_2", "lab", 10, "Culture Lab 2", "Laboratorium kultur 2", dev=[("terminal", "culture_terminal")]),
           Room("cells", "containment", 12, "Containment Cells", "Cele izolacyjne", dev=[("containment_console", "culture_vault")], door="secure", enemy=True)]
m.middle = [Room("field_room", "maintenance", 10, "Field Generators", "Generatory pola", dev=[("electrical_panel", "field_panel")]),
            Room("observation", "control", 10, "Observation", "Obserwatorium", dev=[("evac_console", "burn_radio")]),
            Room("medbay", "medical", 8, "Medbay", "Ambulatorium")]
m.south = [GEN_ROOM(), Room("supplies", "storage", 10, "Supplies", "Zaopatrzenie"),
           Room("incubators", "freezer", 10, "Incubators", "Inkubatory", enemy=True),
           Room("offices", "office", 8, "Researchers' Offices", "Biura naukowców")]
reach(m, "reach_decon", "decon", ("Pass through decontamination", "Przejdź przez dekontaminację"), ("The only way into Sector 7.", "Jedyne wejście do sektora 7."))
power_up(m)
interact(m, "culture_logs", "culture_terminal", ("Read the culture logs", "Przeczytaj dziennik kultur"),
         ("They will tell you which culture is still alive.", "Dowiesz się, która kultura wciąż żyje."), dur=6.0, xp=90)
parts(m, "field_parts", ("Find parts for the field generator", "Znajdź części do generatora pola"),
      ("Labs and supplies should have spares.", "W laboratoriach i zaopatrzeniu powinny być części."))
deliver(m, "repair_field", "field_panel", "field_parts", ("Repair the containment field", "Napraw pole izolacyjne"), ("Without the field the vault won't open.", "Bez pola skarbiec się nie otworzy."))
interact(m, "extract_culture", "culture_vault", ("Extract a live culture", "Wydobądź żywą kulturę"),
         ("It will wake everything in the cells.", "Obudzi wszystko w celach."), dur=8.0, noise=12.0, events_on_start=["hunter_alert"], grants_item="sample_case", xp=150, threat_on_complete=0.1)
carry(m, "secure_culture", "sample_case", ("Carry the culture out", "Wynieś kulturę"), ("Do not drop it.", "Nie upuść jej."))
finale(m, "burn_radio", ("Tell them to hold the burn", "Każ wstrzymać spalanie"), ("The observation room radio reaches the burn team.", "Radio w obserwatorium łączy z ekipą spalającą."), survive=75)
opt_drives(m, ("Recover the genome drives", "Odzyskaj dyski z genomem"), ("Two drives with the full sequence.", "Dwa dyski z pełną sekwencją."))
m.note("Culture H-7 doubled its mass overnight. It pressed against the glass when Dr. Ilić walked in.", "Kultura H-7 podwoiła masę w nocy. Przywarła do szyby, gdy weszła dr Ilić.")
m.note("If the field fails: do NOT open the cells. Do NOT turn off the lights. It hates the cold, not the light. We were wrong.", "Jeśli pole padnie: NIE otwierać cel. NIE gasić świateł. Nie znosi zimna, nie światła. Myliliśmy się.")
m.note("Burn order authorised for 05:00. Anyone still inside at 05:00 is classified as contaminated.", "Rozkaz spalenia zatwierdzony na 05:00. Każdy, kto będzie w środku o 05:00, zostaje uznany za skażonego.")

# =============================================================================================
# 8. PUMP STATION 6 - sewers
m = mission("pump_station", "Pump Station 6", "Przepompownia 6",
            "The river is rising and Pump Station 6 is dead. Close the flood valves, restart the main pump and hold on while the tunnels drain - whatever lives down there is coming up with the water.",
            "Rzeka wzbiera, a Przepompownia 6 stoi. Zamknij zawory przeciwpowodziowe, uruchom główną pompę i wytrzymaj, aż tunele się osuszą - to, co tam żyje, wypłynie razem z wodą.",
            "Riverside Pump Station 6", "Przepompownia 6 nad rzeką", unlock=4, minutes=14, extraction="west",
            depths=(9, 7, 9), filler=("tunnel", "pump", "tunnel"),
            yards=(("River Embankment", "Nabrzeże rzeki"), ("Overflow Channel", "Kanał przelewowy")))
m.north = [Room("control", "control", 10, "Pump Control", "Sterownia pomp", tags=["pump_control"], dev=[("alarm_panel", "alarm_panel"), ("evac_console", "pump_radio")]),
           Room("valve_a", "pump", 10, "Valve Chamber A", "Komora zaworów A", dev=[("electrical_panel", "valve_a")]),
           Room("intake", "tunnel", 10, "Intake Tunnel", "Tunel wlotowy", enemy=True, door="heavy"),
           Room("valve_b", "pump", 10, "Valve Chamber B", "Komora zaworów B", dev=[("electrical_panel", "valve_b")])]
m.middle = [Room("main_pump", "pump", 14, "Main Pump Hall", "Hala pompy głównej", dev=[("electrical_panel", "main_pump")], enemy=True),
            Room("workshop", "maintenance", 10, "Workshop", "Warsztat")]
m.south = [GEN_ROOM(), Room("stores", "storage", 10, "Stores", "Magazyn"),
           Room("sump", "tunnel", 10, "Sump Tunnel", "Tunel osadnika", enemy=True, door="heavy"),
           Room("crew_room", "office", 10, "Crew Room", "Pokój załogi", dev=[("terminal", "server_terminal")])]
reach(m, "reach_control", "pump_control", ("Get to pump control", "Dotrzyj do sterowni pomp"), ("North side of the station.", "Północna strona przepompowni."))
power_up(m)
interact(m, "valve_a", "valve_a", ("Close flood valve A", "Zamknij zawór A"), ("Valve chamber A, north corridor.", "Komora zaworów A, północny korytarz."), dur=5.0, noise=10.0, xp=80)
interact(m, "valve_b", "valve_b", ("Close flood valve B", "Zamknij zawór B"), ("Valve chamber B, at the east end.", "Komora zaworów B, na wschodnim końcu."), dur=5.0, noise=10.0, xp=80)
parts(m, "pump_parts", ("Find parts for the main pump", "Znajdź części do pompy głównej"), ("The stores and the workshop.", "Magazyn i warsztat."))
deliver(m, "restart_pump", "main_pump", "pump_parts", ("Restart the main pump", "Uruchom pompę główną"),
        ("The pump is loud. Everything in the tunnels will know.", "Pompa jest głośna. Wszystko w tunelach się dowie."), dur=8.0, noise=16.0, events_on_start=["hunter_alert"])
finale(m, "pump_radio", ("Report the station is running", "Zgłoś uruchomienie stacji"), ("Pump control has the city radio.", "Sterownia ma radio miejskie."), survive=70,
       survive_text=(("Hold out while the tunnels drain", "Wytrzymaj, aż tunele się osuszą"), ("Something is coming up with the water.", "Coś wypływa razem z wodą.")))
opt_server(m, "server_terminal", ("Download the flow sensors", "Pobierz dane z czujników przepływu"), ("Something big blocked the intake last night.", "Coś dużego zablokowało wlot zeszłej nocy."))
m.note("Intake grate found bent OUTWARD. 40 mm steel. Nothing in the river can do that.", "Krata wlotu wygięta NA ZEWNĄTRZ. Stal 40 mm. Nic w rzece tego nie zrobi.")
m.note("Crew: stay out of the sump tunnel. Marek went in for the radio and we heard him laughing. Marek never laughs.", "Załoga: nie wchodźcie do tunelu osadnika. Marek poszedł po radio i słyszeliśmy, jak się śmieje. Marek nigdy się nie śmieje.")
m.note("Water temperature at intake: 19 C. River temperature: 4 C. Something warm is living in the pipes.", "Temperatura wody na wlocie: 19 C. Temperatura rzeki: 4 C. W rurach żyje coś ciepłego.")

# =============================================================================================
# 9. BLACKOUT TOWER - office tower
m = mission("blackout_tower", "Blackout Tower", "Wieża w ciemności",
            "Vantage Tower is where Kessler's money men worked late. Restore power, pull the access logs and copy the executive server before the board's private security arrives to clean up.",
            "W Vantage Tower do późna pracowali ludzie od pieniędzy Kesslera. Przywróć zasilanie, wyciągnij logi dostępu i skopiuj serwer zarządu, zanim prywatna ochrona przyjedzie posprzątać.",
            "Vantage Tower", "Vantage Tower", unlock=5, minutes=15, threat=0.05, extraction="both",
            filler=("office", "office", "office"),
            yards=(("Plaza", "Plac przed wieżą"), ("Underground Car Park", "Parking podziemny")),
            loot_bias={"access_decoder": 0.8})
m.north = [Room("atrium", "lobby", 12, "Atrium", "Atrium", tags=["atrium"]),
           Room("open_office", "office", 14, "Open Office", "Open space", link=True),
           Room("boardroom", "office", 10, "Boardroom", "Sala zarządu", loot=["research", "general"], enemy=True)]
m.middle = [Room("security", "security", 8, "Security Desk", "Recepcja ochrony", dev=[("terminal", "access_logs"), ("alarm_panel", "alarm_panel")]),
            Room("exec_server", "server", 10, "Executive Server", "Serwer zarządu", dev=[("terminal", "exec_server")], door="secure"),
            Room("archive", "archive", 10, "Records", "Dokumentacja", loot=["research", "keycard_spawn"]),
            Room("break_room", "office", 8, "Break Room", "Kuchnia", dev=[("terminal", "server_terminal")])]
m.south = [Room("maintenance", "maintenance", 10, "Building Services", "Obsługa budynku", dev=[("breaker", "power_breaker")]),
           Room("storage", "storage", 10, "Storage", "Magazyn"),
           Room("mailroom", "office", 10, "Mail Room", "Kancelaria", dev=[("evac_console", "pickup_phone")], enemy=True)]
reach(m, "reach_atrium", "atrium", ("Enter the tower", "Wejdź do wieży"), ("The atrium doors are jammed open.", "Drzwi atrium są zablokowane w otwarciu."))
m.obj("power", "interact", ("Restore building power", "Przywróć zasilanie budynku"),
      ("Building services, south corridor. No generator - just the breaker.", "Obsługa budynku, południowy korytarz. Bez generatora - tylko wyłącznik."),
      target_tag="power_breaker", duration=2.0, sets_flag="power_main", threat_on_complete=0.06, reward_xp=70)
interact(m, "access_logs", "access_logs", ("Pull the access logs", "Wyciągnij logi dostępu"), ("The security desk shows who was here last night.", "Recepcja ochrony pokaże, kto tu był zeszłej nocy."), dur=6.0, xp=90)
collect(m, "exec_key", "keycard", 1, "keycard_spawn", ("Find an executive keycard", "Znajdź kartę zarządu"), ("The logs show where it was used last.", "Logi pokazują, gdzie użyto jej ostatnio."), reveal=True, spare=0)
interact(m, "copy_server", "exec_server", ("Copy the executive server", "Skopiuj serwer zarządu"),
         ("It takes time. The fans will spin up and everything will hear.", "To potrwa. Wentylatory ruszą i wszystko to usłyszy."), dur=10.0, noise=12.0, events_on_start=["hunter_alert"], xp=150, threat_on_complete=0.1)
collect(m, "backups", "data_drive", 2, "research", ("Grab the offline backups", "Zabierz kopie offline"), ("Two drives the board kept off the network.", "Dwa dyski, które zarząd trzymał poza siecią."), reveal=True, xp=120)
finale(m, "pickup_phone", ("Call for pickup", "Wezwij transport"), ("The mail room line goes outside the building network.", "Linia z kancelarii omija sieć budynku."), survive=70)
opt_server(m, "server_terminal", ("Erase your faces from the cameras", "Usuń swoje twarze z kamer"), ("The board's security will check the footage.", "Ochrona zarządu sprawdzi nagrania."))
m.note("Board minutes: 'Liability for the Kessler incident will be transferred to the night staff.' Unanimous.", "Protokół zarządu: 'Odpowiedzialność za incydent w Kesslerze zostanie przeniesiona na nocną zmianę.' Jednogłośnie.")
m.note("Cleaner, 23rd floor: someone is walking above the ceiling tiles. There is no 24th floor.", "Sprzątaczka, 23. piętro: ktoś chodzi nad płytami sufitu. Nie ma 24. piętra.")
m.note("Security: lifts disabled by order of the board. Stairs locked. Nobody leaves until the auditors arrive.", "Ochrona: windy wyłączone decyzją zarządu. Schody zamknięte. Nikt nie wychodzi do przyjazdu audytorów.")

# =============================================================================================
# 10. IRON GATE - prison
m = mission("iron_gate", "Iron Gate", "Żelazna brama",
            "Blackmoor Penitentiary took Kessler's 'transfers'. One of them is still alive in solitary - and two of the things that came for him are walking the cell blocks.",
            "Do zakładu karnego Blackmoor trafiali 'transferowani' z Kesslera. Jeden z nich wciąż żyje w izolatce - a po blokach chodzą dwa stwory, które po niego przyszły.",
            "Blackmoor Penitentiary", "Zakład karny Blackmoor", unlock=5, minutes=17, threat=0.05, hunters=2, release=90.0, extraction="west",
            depths=(10, 7, 9), filler=("containment", "hall", "storage"),
            yards=(("Gatehouse", "Wartownia przy bramie"), ("Exercise Yard", "Spacerniak")))
m.north = [Room("guard_post", "security", 8, "Guard Post", "Posterunek", tags=["guard_post"], dev=[("alarm_panel", "alarm_panel")]),
           Room("block_a", "containment", 14, "Cell Block A", "Blok A", enemy=True, link=True),
           Room("block_c", "containment", 12, "Cell Block C", "Blok C", dev=[("containment_console", "block_c_console")], door="secure")]
m.middle = [Room("mess", "hall", 12, "Mess Hall", "Stołówka"),
            Room("infirmary", "medical", 8, "Infirmary", "Izba chorych"),
            Room("control", "control", 10, "Central Control", "Centrala", dev=[("terminal", "transfer_terminal"), ("evac_console", "prison_radio")])]
m.south = [GEN_ROOM(), Room("solitary", "containment", 10, "Solitary", "Izolatki", tags=["solitary"], enemy=True),
           Room("warden", "office", 10, "Warden's Office", "Gabinet naczelnika", loot=["keycard_spawn", "research"]),
           Room("laundry", "storage", 8, "Laundry", "Pralnia")]
reach(m, "reach_guard", "guard_post", ("Get past the guard post", "Przejdź przez posterunek"), ("North corridor, first door.", "Północny korytarz, pierwsze drzwi."))
power_up(m)
interact(m, "transfer_record", "transfer_terminal", ("Find the transfer record", "Znajdź rejestr transferów"), ("Central control lists where the Kessler prisoner is held.", "Centrala ma zapis, gdzie trzymają więźnia z Kesslera."), dur=6.0, xp=90)
collect(m, "master_key", "keycard", 1, "keycard_spawn", ("Find the master keycard", "Znajdź kartę główną"), ("The warden kept one. Guards kept others.", "Naczelnik miał jedną. Strażnicy kolejne."), reveal=True, spare=0)
interact(m, "open_block_c", "block_c_console", ("Open cell block C", "Otwórz blok C"), ("It will open every cell at once.", "Otworzy wszystkie cele naraz."), dur=8.0, noise=14.0, events_on_start=["hunter_alert"], xp=140, threat_on_complete=0.1)
reach(m, "reach_solitary", "solitary", ("Find the survivor in solitary", "Znajdź ocalałego w izolatce"), ("The south wing. Whatever is left of him.", "Południowe skrzydło. Cokolwiek z niego zostało."), xp=100)
finale(m, "prison_radio", ("Radio the transport", "Wezwij transport przez radio"), ("Central control can still reach the outside.", "Centrala wciąż ma łączność ze światem."), survive=80,
       extract_text=(("Get to the gatehouse", "Dotrzyj do wartowni przy bramie"), ("Back the way you came.", "Z powrotem tą samą drogą.")))
opt_drives(m, ("Take the warden's files", "Zabierz akta naczelnika"), ("Two drives with every Kessler transfer.", "Dwa dyski z każdym transferem z Kesslera."))
m.note("Transfer 14 from Kessler: does not eat. Does not sleep. Asks every guard what time the night shift ends.", "Transfer 14 z Kesslera: nie je. Nie śpi. Pyta każdego strażnika, o której kończy się nocna zmiana.")
m.note("Block A head count 02:00: 38. Block A head count 03:00: 38. Block A cell doors: all open.", "Apel blok A 02:00: 38. Apel blok A 03:00: 38. Drzwi cel bloku A: wszystkie otwarte.")
m.note("Warden: I have locked myself in. If you read this, the master key is in the drawer. Leave me here.", "Naczelnik: zamknąłem się. Jeśli to czytasz, karta główna jest w szufladzie. Zostaw mnie tu.")

# =============================================================================================
# 11. GHOST SIGNAL - observatory
m = mission("ghost_signal", "Ghost Signal", "Sygnał widmo",
            "Kestrel Ridge Observatory picked up a signal coming from under Kessler. It repeats the voices of the people who disappeared. Trace it, realign the dish and answer.",
            "Obserwatorium Kestrel Ridge odebrało sygnał spod Kesslera. Powtarza głosy ludzi, którzy zaginęli. Namierz go, ustaw antenę i odpowiedz.",
            "Kestrel Ridge Observatory", "Obserwatorium Kestrel Ridge", unlock=6, minutes=15, threat=0.05, extraction="east",
            filler=("office", "lab", "storage"),
            yards=(("Mountain Road", "Górska droga"), ("Helipad", "Lądowisko")))
m.north = [Room("lobby", "lobby", 8, "Visitor Centre", "Centrum dla zwiedzających", tags=["visitor_centre"]),
           Room("dish_control", "control", 12, "Dish Control", "Sterownia anteny", dev=[("terminal", "answer_console"), ("alarm_panel", "alarm_panel")]),
           Room("receiver", "server", 10, "Receiver Room", "Odbiorniki", dev=[("terminal", "trace_terminal")]),
           Room("drive_room", "maintenance", 10, "Dish Drive", "Napęd anteny", dev=[("electrical_panel", "dish_drive")], enemy=True)]
m.middle = [Room("lab", "lab", 10, "Signal Lab", "Laboratorium sygnałów"),
            Room("archive", "archive", 10, "Tape Archive", "Archiwum taśm", enemy=True),
            Room("quarters", "office", 10, "Staff Quarters", "Kwatery", dev=[("evac_console", "helipad_radio")])]
m.south = [GEN_ROOM(), Room("workshop", "maintenance", 10, "Workshop", "Warsztat"),
           Room("stores", "storage", 10, "Stores", "Magazyn"), Room("canteen", "office", 10, "Canteen", "Stołówka", enemy=True)]
reach(m, "reach_lobby", "visitor_centre", ("Enter the observatory", "Wejdź do obserwatorium"), ("The visitor centre is unlocked.", "Centrum dla zwiedzających jest otwarte."))
power_up(m)
interact(m, "trace", "trace_terminal", ("Trace the signal", "Namierz sygnał"), ("The receiver room is recording it right now.", "Odbiorniki właśnie go nagrywają."), dur=8.0, xp=100)
parts(m, "drive_parts", ("Find parts for the dish drive", "Znajdź części do napędu anteny"), ("Workshop and stores.", "Warsztat i magazyn."), pool=("circuit_board", "capacitor", "fuse"))
deliver(m, "realign", "dish_drive", "drive_parts", ("Realign the dish", "Ustaw antenę"), ("The drive motor is loud enough to hear in the valley.", "Silnik napędu słychać w całej dolinie."), dur=8.0, noise=16.0)
interact(m, "answer", "answer_console", ("Answer the signal", "Odpowiedz na sygnał"), ("Hold the console. Whatever answers back, keep holding.", "Trzymaj konsolę. Cokolwiek odpowie, trzymaj dalej."), dur=12.0, noise=14.0, events_on_start=["hunter_alert"], xp=160, threat_on_complete=0.12)
finale(m, "helipad_radio", ("Call the helicopter", "Wezwij śmigłowiec"), ("Staff quarters have the emergency radio.", "W kwaterach jest radio awaryjne."), survive=75,
       extract_text=(("Get to the helipad", "Dotrzyj na lądowisko"), ("East of the observatory.", "Na wschód od obserwatorium.")))
opt_drives(m, ("Recover the original recordings", "Odzyskaj oryginalne nagrania"), ("Two tapes the director hid.", "Dwie taśmy schowane przez dyrektora."))
m.note("Signal log: 1420 MHz, repeating every 9 minutes. Today it said my name. In my mother's voice.", "Dziennik sygnału: 1420 MHz, co 9 minut. Dziś wypowiedział moje imię. Głosem mojej matki.")
m.note("The signal is not coming from space. Triangulation puts it 400 m under the Kessler facility.", "Sygnał nie pochodzi z kosmosu. Triangulacja wskazuje 400 m pod placówką Kessler.")
m.note("Director: do not answer it. It is not asking for help. It is learning how we talk.", "Dyrektor: nie odpowiadajcie. To nie prośba o pomoc. Ono uczy się, jak rozmawiamy.")

# =============================================================================================
# 12. HOLLOW MINE
m = mission("hollow_mine", "Hollow Mine", "Pusta kopalnia",
            "Shaft 3 of the Gorska mine broke into a cavern nobody mapped. Eleven miners went silent. Find what's left of them, fix the lift winch and get everyone out of the dark.",
            "Szyb 3 kopalni Górska przebił się do jaskini, której nikt nie zmapował. Jedenastu górników zamilkło. Znajdź, co z nich zostało, napraw wyciągarkę windy i wyprowadź wszystkich z ciemności.",
            "Gorska Mine, Shaft 3", "Kopalnia Górska, szyb 3", unlock=6, minutes=16, threat=0.05, hunters=2, release=100.0, extraction="west",
            height=3.6, depths=(9, 7, 9), filler=("tunnel", "tunnel", "tunnel"),
            yards=(("Pithead", "Nadszybie"), ("Ventilation Shaft", "Szyb wentylacyjny")))
m.north = [Room("lamp_room", "security", 8, "Lamp Room", "Lampownia", tags=["lamp_room"], dev=[("alarm_panel", "alarm_panel")]),
           Room("gallery_1", "tunnel", 14, "Gallery 1", "Chodnik 1", enemy=True),
           Room("foreman", "office", 8, "Foreman's Hut", "Sztygarówka", dev=[("terminal", "foreman_terminal")]),
           Room("collapse", "tunnel", 10, "The Collapse", "Zawał", tags=["collapse"], enemy=True)]
m.middle = [Room("cavern", "hall", 14, "Cavern", "Jaskinia", enemy=True),
            Room("lift_house", "maintenance", 10, "Lift Winch", "Wyciągarka windy", dev=[("electrical_panel", "lift_winch"), ("evac_console", "lift_console")])]
m.south = [GEN_ROOM("generator_room", "Underground Substation", "Podstacja dołowa"),
           Room("drainage", "pump", 10, "Drainage", "Odwadnianie"),
           Room("stores", "storage", 10, "Powder Stores", "Magazyn materiałów"),
           Room("first_aid", "medical", 10, "First Aid Chamber", "Komora ratunkowa")]
reach(m, "reach_lamp_room", "lamp_room", ("Collect lamps in the lamp room", "Weź lampy w lampowni"), ("First door on the north gallery.", "Pierwsze drzwi w północnym chodniku."))
power_up(m, hint_gen=("The underground substation is south.", "Podstacja dołowa jest na południu."))
reach(m, "find_miners", "collapse", ("Find the trapped miners", "Znajdź uwięzionych górników"), ("Their last position was at the collapse, east end of gallery 1.", "Ostatnio byli przy zawale, na wschodnim końcu chodnika 1."), xp=100)
interact(m, "foreman_log", "foreman_terminal", ("Read the foreman's log", "Przeczytaj dziennik sztygara"), ("The foreman's hut. Find out what they broke into.", "Sztygarówka. Dowiedz się, do czego się przebili."), dur=6.0, xp=90)
parts(m, "winch_parts", ("Find parts for the winch", "Znajdź części do wyciągarki"), ("Powder stores and drainage.", "Magazyn materiałów i odwadnianie."))
deliver(m, "fix_winch", "lift_winch", "winch_parts", ("Fix the lift winch", "Napraw wyciągarkę"), ("The winch room is in the middle of the mine. Loud work.", "Wyciągarka jest w środku kopalni. Głośna robota."), dur=8.0, noise=14.0)
finale(m, "lift_console", ("Call the cage up", "Wezwij klatkę"), ("Use the lift console in the winch room.", "Użyj konsoli windy przy wyciągarce."), survive=80, dur=6.0,
       survive_text=(("Hold out until the cage comes down", "Wytrzymaj, aż klatka zjedzie"), ("The cage takes time. They don't.", "Klatka jedzie powoli. One nie.")),
       extract_text=(("Ride the cage at the pithead", "Wsiadaj do klatki przy nadszybiu"), ("Back to where you came down.", "Tam, gdzie zjechaliście.")))
opt_drives(m, ("Recover the survey maps", "Odzyskaj mapy z pomiarów"), ("Two drives with the cavern survey.", "Dwa dyski z pomiarem jaskini."))
m.note("Foreman: the drill broke through at 340 m. Warm air came out. It smelled like a hospital.", "Sztygar: wiertło przebiło się na 340 m. Wyleciało ciepłe powietrze. Pachniało jak w szpitalu.")
m.note("We counted eleven lamps going into the cavern. Twelve came back out.", "Do jaskini weszło jedenaście lamp. Wyszło dwanaście.")
m.note("Do not sit in the dark. If your lamp dies, sing. They don't like singing.", "Nie siedź po ciemku. Jak lampa zgaśnie, śpiewaj. One nie lubią śpiewu.")

# =============================================================================================
# 13. SHELTER 12 - civil defence bunker
m = mission("shelter_twelve", "Shelter 12", "Schron 12",
            "Civil Defence Shelter 12 was sealed with three hundred people inside. The air filters stopped yesterday. Restart them, find the shelter roster and open the blast door from the inside.",
            "Schron obrony cywilnej nr 12 zamknięto z trzystoma osobami w środku. Wczoraj stanęły filtry powietrza. Uruchom je, znajdź listę mieszkańców i otwórz drzwi przeciwwybuchowe od środka.",
            "Civil Defence Shelter 12", "Schron obrony cywilnej nr 12", unlock=7, minutes=16, threat=0.05, hunters=2, release=90.0, extraction="west",
            height=3.6, depths=(9, 8, 9), filler=("hall", "office", "storage"),
            yards=(("Blast Door", "Drzwi przeciwwybuchowe"), ("Emergency Hatch", "Właz awaryjny")))
m.north = [Room("airlock", "security", 8, "Airlock", "Śluza", tags=["airlock"], dev=[("alarm_panel", "alarm_panel"), ("evac_console", "blast_door")]),
           Room("dorm_a", "hall", 14, "Dormitory A", "Sypialnia A", enemy=True, link=True),
           Room("dorm_b", "hall", 12, "Dormitory B", "Sypialnia B")]
m.middle = [Room("filters", "pump", 12, "Air Filtration", "Filtrowentylacja", dev=[("electrical_panel", "air_filters")]),
            Room("command", "control", 10, "Shelter Command", "Dowództwo schronu", dev=[("terminal", "roster_terminal")]),
            Room("infirmary", "medical", 10, "Infirmary", "Izba chorych", enemy=True)]
m.south = [GEN_ROOM(), Room("food_store", "freezer", 10, "Food Store", "Magazyn żywności"),
           Room("armoury", "storage", 8, "Armoury", "Zbrojownia", loot=["tools", "component_spawn", "keycard_spawn"]),
           Room("records", "archive", 10, "Records", "Ewidencja", dev=[("terminal", "server_terminal")], enemy=True)]
reach(m, "reach_airlock", "airlock", ("Get through the airlock", "Przejdź przez śluzę"), ("The emergency hatch leads into the airlock.", "Właz awaryjny prowadzi do śluzy."))
power_up(m)
parts(m, "filter_parts", ("Find parts for the air filters", "Znajdź części do filtrów"), ("The armoury and the stores.", "Zbrojownia i magazyny."))
deliver(m, "restart_filters", "air_filters", "filter_parts", ("Restart the air filters", "Uruchom filtry powietrza"), ("The filter hall is in the middle of the shelter.", "Hala filtrów jest w środku schronu."), dur=8.0, noise=14.0)
interact(m, "roster", "roster_terminal", ("Find the shelter roster", "Znajdź listę mieszkańców"), ("Shelter command. Find out how many are left.", "Dowództwo schronu. Sprawdź, ilu zostało."), dur=6.0, xp=100)
collect(m, "door_key", "keycard", 1, "keycard_spawn", ("Find the blast door key", "Znajdź klucz do drzwi"), ("The commander kept it in the armoury.", "Komendant trzymał go w zbrojowni."), reveal=True, spare=0)
collect(m, "logbooks", "data_drive", 2, "research", ("Take the commander's logbooks", "Zabierz dzienniki komendanta"), ("Two drives. Somebody has to know what happened here.", "Dwa dyski. Ktoś musi wiedzieć, co tu się stało."), reveal=True, xp=110)
finale(m, "blast_door", ("Open the blast door", "Otwórz drzwi przeciwwybuchowe"), ("The airlock controls the main door.", "Śluza steruje głównymi drzwiami."), survive=80, dur=6.0,
       survive_text=(("Hold out while the door cycles", "Wytrzymaj, aż drzwi się otworzą"), ("Two minutes of grinding steel. Everything heard it.", "Dwie minuty zgrzytu stali. Wszystko to słyszało.")),
       extract_text=(("Get out through the blast door", "Wyjdź przez drzwi przeciwwybuchowe"), ("West side. Don't look back.", "Zachodnia strona. Nie oglądaj się.")))
opt_server(m, "server_terminal", ("Send the roster to the city", "Wyślij listę do miasta"), ("Families are waiting for names.", "Rodziny czekają na nazwiska."))
m.note("Day 3: headcount 297. Day 4: headcount 297. Day 5: headcount 301. Nobody came in.", "Dzień 3: stan 297. Dzień 4: stan 297. Dzień 5: stan 301. Nikt nie wszedł.")
m.note("Commander: dormitory A is closed. Do not ask why. Do not listen at the door.", "Komendant: sypialnia A zamknięta. Nie pytać dlaczego. Nie podsłuchiwać pod drzwiami.")
m.note("Child's drawing pinned to the wall: a tall grey man with too many fingers, holding everyone's hands.", "Rysunek dziecka na ścianie: wysoki szary pan ze zbyt wieloma palcami trzyma wszystkich za ręce.")

# =============================================================================================
# 14. TOXIC TIDE - chemical plant
m = mission("toxic_tide", "Toxic Tide", "Toksyczna fala",
            "Vel-Chem made the sedatives that kept THE HUNTER asleep. The plant is leaking and two of them are awake inside it. Seal the leak, run the scrubbers and synthesise one last batch.",
            "Vel-Chem produkował środki, które utrzymywały ŁOWCĘ w uśpieniu. Zakład przecieka, a w środku obudziły się dwa z nich. Uszczelnij wyciek, uruchom płuczki i zsyntetyzuj ostatnią partię.",
            "Vel-Chem Plant", "Zakłady Vel-Chem", unlock=7, minutes=17, threat=0.055, hunters=2, release=85.0, extraction="both",
            height=4.6, depths=(10, 7, 9), filler=("maintenance", "lab", "storage"),
            yards=(("Tanker Bay", "Stanowisko cystern"), ("Rail Siding", "Bocznica kolejowa")))
m.north = [Room("gatehouse", "security", 8, "Plant Security", "Ochrona zakładu", tags=["plant_security"], dev=[("alarm_panel", "alarm_panel"), ("evac_console", "plant_radio")]),
           Room("reactor_hall", "hall", 16, "Reactor Hall", "Hala reaktorów", dev=[("electrical_panel", "leak_valve")], enemy=True, door="heavy"),
           Room("synthesis", "lab", 12, "Synthesis Lab", "Laboratorium syntezy", dev=[("terminal", "synthesis_terminal")])]
m.middle = [Room("scrubbers", "pump", 12, "Scrubbers", "Płuczki", dev=[("electrical_panel", "scrubber_panel")]),
            Room("control", "control", 10, "Process Control", "Sterownia procesu", dev=[("terminal", "server_terminal")]),
            Room("tank_farm", "pump", 10, "Tank Farm", "Zbiorniki", dev=[("electrical_panel", "leak_valve")], enemy=True)]
m.south = [GEN_ROOM(), Room("warehouse", "storage", 12, "Drum Warehouse", "Magazyn beczek"),
           Room("qa_lab", "lab", 10, "QA Lab", "Laboratorium jakości", enemy=True),
           Room("locker", "office", 8, "Locker Room", "Szatnia")]
reach(m, "reach_security", "plant_security", ("Check in at plant security", "Zamelduj się w ochronie"), ("The gatehouse, north-west.", "Wartownia, północny zachód."))
power_up(m)
interact(m, "seal_leak", "leak_valve", ("Seal the leak", "Uszczelnij wyciek"), ("A valve in the reactor hall or the tank farm is stuck open.", "Zawór w hali reaktorów albo w zbiornikach się zablokował."), dur=6.0, noise=10.0, xp=100)
parts(m, "scrubber_parts", ("Find parts for the scrubbers", "Znajdź części do płuczek"), ("Warehouse and labs.", "Magazyn i laboratoria."))
deliver(m, "run_scrubbers", "scrubber_panel", "scrubber_parts", ("Run the scrubbers", "Uruchom płuczki"), ("Clear the air before you synthesise.", "Oczyść powietrze przed syntezą."), dur=8.0, noise=14.0)
interact(m, "synthesise", "synthesis_terminal", ("Synthesise the sedative", "Zsyntetyzuj środek usypiający"), ("It takes time and it smells. They will come.", "To potrwa i będzie pachnieć. Przyjdą."), dur=10.0, noise=12.0, events_on_start=["hunter_alert"], grants_item="sample_case", xp=160, threat_on_complete=0.12)
carry(m, "carry_batch", "sample_case", ("Carry the batch out", "Wynieś partię"), ("Last batch on earth. Don't drop it.", "Ostatnia partia na świecie. Nie upuść jej."))
finale(m, "plant_radio", ("Call the hazmat team", "Wezwij ekipę chemiczną"), ("Plant security has the radio.", "Ochrona zakładu ma radio."), survive=80)
opt_server(m, "server_terminal", ("Download the formula", "Pobierz recepturę"), ("Process control still has the full formula.", "Sterownia procesu ma jeszcze pełną recepturę."))
m.note("Batch 88 shipped to Kessler 18:00. Batch 89 cancelled by order. Subject dosage halved 'to observe behaviour'.", "Partia 88 wysłana do Kesslera 18:00. Partia 89 anulowana poleceniem. Dawkę dla obiektu zmniejszono o połowę, 'aby obserwować zachowanie'.")
m.note("Tank 4 is leaking upward. Liquid does not leak upward.", "Zbiornik 4 przecieka do góry. Ciecz nie przecieka do góry.")
m.note("Chemist: it sleeps when the dose is right. It dreams when the dose is low. We are in its dream now.", "Chemik: śpi, gdy dawka jest dobra. Śni, gdy dawka jest za mała. Jesteśmy teraz w jego śnie.")

# =============================================================================================
# 15. FINAL SHIFT - Kessler deep labs (finale)
m = mission("final_shift", "Final Shift", "Ostatnia zmiana",
            "Everything leads back to Kessler. Under the facility is the nest where THE HUNTER was made - and where more are growing. Rebuild the containment grid, seal the nest and walk out at dawn.",
            "Wszystko prowadzi z powrotem do Kesslera. Pod placówką jest gniazdo, w którym powstał ŁOWCA - i gdzie rosną kolejne. Odbuduj siatkę izolacyjną, zapieczętuj gniazdo i wyjdź o świcie.",
            "Kessler Deep Labs", "Kessler - laboratoria głębokie", unlock=8, minutes=20, threat=0.06, hunters=3, release=80.0, extraction="east",
            width=46, height=4.4, depths=(10, 8, 10), filler=("lab", "containment", "maintenance"),
            yards=(("Service Lift", "Winda serwisowa"), ("Surface Exit", "Wyjście na powierzchnię")))
m.north = [Room("checkpoint", "security", 8, "Deep Checkpoint", "Głęboki posterunek", tags=["deep_checkpoint"], dev=[("terminal", "deep_security"), ("alarm_panel", "alarm_panel")]),
           Room("genetics", "lab", 12, "Genetics", "Genetyka", link=True),
           Room("nursery", "containment", 14, "The Nursery", "Żłobek", enemy=True, door="secure"),
           Room("nest", "containment", 12, "The Nest", "Gniazdo", dev=[("containment_console", "nest_console")], door="secure", enemy=True)]
m.middle = [Room("grid_a", "maintenance", 10, "Grid Junction A", "Węzeł siatki A", dev=[("electrical_panel", "grid_panel")]),
            Room("origin_lab", "server", 12, "Origin Servers", "Serwery źródłowe", dev=[("terminal", "origin_terminal")]),
            Room("grid_b", "maintenance", 10, "Grid Junction B", "Węzeł siatki B", dev=[("electrical_panel", "grid_panel")]),
            Room("observation", "control", 10, "Observation Deck", "Taras obserwacyjny", dev=[("evac_console", "surface_radio")])]
m.south = [GEN_ROOM("generator_room", "Deep Generator", "Generator głębinowy"),
           Room("cold_store", "freezer", 12, "Specimen Cold Store", "Chłodnia okazów", enemy=True),
           Room("stores", "storage", 10, "Stores", "Magazyn"),
           Room("director", "office", 10, "Director's Office", "Gabinet dyrektora", loot=["keycard_spawn", "research"])]
reach(m, "reach_checkpoint", "deep_checkpoint", ("Reach the deep checkpoint", "Dotrzyj do głębokiego posterunku"), ("The service lift brought you down. Go east.", "Winda serwisowa zwiozła was na dół. Idźcie na wschód."))
power_up(m, hint_gen=("The deep generator is in the south wing.", "Generator głębinowy jest w południowym skrzydle."))
interact(m, "deep_security", "deep_security", ("Break the deep security", "Złam zabezpieczenia"), ("The checkpoint terminal controls the secure doors.", "Terminal posterunku steruje drzwiami bezpieczeństwa."), dur=6.0, events_on_complete=["alarm"], xp=90)
interact(m, "origin", "origin_terminal", ("Find out where it came from", "Dowiedz się, skąd się wzięło"), ("The origin servers hold the first entry.", "Serwery źródłowe mają pierwszy wpis."), dur=10.0, noise=6.0, xp=140)
parts(m, "grid_parts", ("Find parts for the containment grid", "Znajdź części do siatki izolacyjnej"), ("Two parts. Search everywhere.", "Dwie części. Przeszukaj wszystko."), xp=100)
deliver(m, "rebuild_grid", "grid_panel", "grid_parts", ("Rebuild the containment grid", "Odbuduj siatkę izolacyjną"), ("Either junction will do. Both are watched.", "Każdy węzeł się nada. Oba są pilnowane."), dur=8.0, noise=14.0)
collect(m, "director_key", "keycard", 1, "keycard_spawn", ("Take the director's keycard", "Zabierz kartę dyrektora"), ("The director never left the deep labs.", "Dyrektor nigdy nie opuścił laboratoriów."), reveal=True, spare=0)
interact(m, "seal_nest", "nest_console", ("Seal the nest", "Zapieczętuj gniazdo"), ("Hold the nest console until the seals lock. They will all come.", "Trzymaj konsolę gniazda, aż pieczęcie się zamkną. Przyjdą wszystkie."), dur=12.0, noise=16.0, events_on_start=["hunter_alert"], grants_item="sample_case", xp=200, threat_on_complete=0.15)
carry(m, "last_sample", "sample_case", ("Take the last sample", "Zabierz ostatnią próbkę"), ("Proof. The only proof.", "Dowód. Jedyny dowód."))
finale(m, "surface_radio", ("Call the surface", "Wezwij powierzchnię"), ("The observation deck reaches the surface team.", "Taras obserwacyjny łączy z ekipą na powierzchni."), survive=90,
       survive_text=(("Survive until dawn", "Przetrwaj do świtu"), ("Ninety seconds to sunrise. It ends tonight.", "Dziewięćdziesiąt sekund do wschodu słońca. To kończy się dziś.")),
       extract_text=(("Walk out into the morning", "Wyjdź w poranek"), ("The surface exit is open. The night shift is over.", "Wyjście na powierzchnię jest otwarte. Nocna zmiana się skończyła.")))
opt_drives(m, ("Recover the origin files", "Odzyskaj akta źródłowe"), ("Two drives with everything Kessler hid.", "Dwa dyski ze wszystkim, co ukrył Kessler."))
m.note("Entry 1, 1986: Found it in the cavern under the mine. It was sleeping. It was cold. We warmed it up.", "Wpis 1, 1986: Znaleźliśmy to w jaskini pod kopalnią. Spało. Było zimne. Ogrzaliśmy je.")
m.note("Director: the nursery has six. They learn from the first one. They learn from us. They learned the night shift schedule.", "Dyrektor: w żłobku jest sześć. Uczą się od pierwszego. Uczą się od nas. Nauczyły się grafiku nocnej zmiany.")
m.note("If you are reading this, you made it further than any of us. Seal the nest. Then go home. Please go home.", "Jeśli to czytasz, zaszedłeś dalej niż ktokolwiek z nas. Zapieczętuj gniazdo. Potem idź do domu. Proszę, idź do domu.")


if __name__ == "__main__":
    for mm in ALL:
        mm.write(ROOT)
    merge_localization(ROOT, ALL)
    print("generated %d missions: %s" % (len(ALL), ", ".join(mm.id for mm in ALL)))
