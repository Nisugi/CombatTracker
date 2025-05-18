/* =========================================================
   DATABASE:  Gemstone IV Combat Tracker
   ========================================================= */

PRAGMA foreign_keys = ON;   -- must be on for FK enforcement
PRAGMA journal_mode  = WAL; -- already true in your Sequel connect

BEGIN;

/* =========================================================
   1.  REFERENCE / LOOK‑UP TABLES
   ========================================================= */

CREATE TABLE creature_types (
    id     SERIAL  PRIMARY KEY,
    noun   TEXT    UNIQUE NOT NULL,
    notes  TEXT
);

CREATE TABLE attack_types (
    id   INTEGER PRIMARY KEY,
    name TEXT     UNIQUE NOT NULL
);

CREATE TABLE resolution_types (
    id   INTEGER PRIMARY KEY,
    name TEXT     UNIQUE NOT NULL
);

CREATE TABLE damage_types (
    id   INTEGER PRIMARY KEY,
    name TEXT     UNIQUE NOT NULL
);

CREATE TABLE flare_types (
    id   INTEGER PRIMARY KEY,
    name TEXT     UNIQUE NOT NULL
);

CREATE TABLE status_types (
    id   INTEGER PRIMARY KEY,
    name TEXT     UNIQUE NOT NULL
);

CREATE TABLE locations (
    id   INTEGER PRIMARY KEY,
    name TEXT     UNIQUE NOT NULL
);

CREATE TABLE critical_types (
    id   INTEGER PRIMARY KEY,
    name TEXT     UNIQUE NOT NULL
);

CREATE TABLE outcome_types (
    id   INTEGER PRIMARY KEY,
    name TEXT     UNIQUE NOT NULL
);

CREATE TABLE defense_types (
    id   INTEGER PRIMARY KEY,
    name TEXT     UNIQUE NOT NULL
);

INSERT OR IGNORE INTO locations (id, name) VALUES
  (1, 'ABDOMEN'),
  (2, 'BACK'),
  (3, 'CHEST'),
  (4, 'HEAD'),
  (5, 'LEFTARM'),
  (6, 'LEFTEYE'),
  (7, 'LEFTFOOT'),
  (8, 'LEFTHAND'),
  (9, 'LEFTLEG'),
  (10, 'NECK'),
  (11, 'NERVES'),
  (12, 'RIGHTARM'),
  (13, 'RIGHTEYE'),
  (14, 'RIGHTFOOT'),
  (15, 'RIGHTHAND'),
  (16, 'RIGHTLEG');

INSERT OR IGNORE INTO resolution_types (id, name) VALUES
  (1, 'AS_DS'),
  (2, 'CS_TD'),
  (3, 'SMR');

INSERT OR IGNORE INTO critical_types (id, name) VALUES
  (1, 'ACID'),
  (2, 'COLD'),
  (3, 'CRUSH'),
  (4, 'DISINTEGRATE'),
  (5, 'DISRUPTION'),
  (6, 'FIRE'),
  (7, 'GRAPPLE'),
  (8, 'IMPACT'),
  (9, 'LIGHTNING'),
  (10, 'NON_CORPOREAL'),
  (11, 'PLASMA'),
  (12, 'PUNCTURE'),
  (13, 'SLASH'),
  (14, 'STEAM'),
  (15, 'UCS_GRAPPLE'),
  (16, 'UCS_JAB'),
  (17, 'UCS_KICK'),
  (18, 'UCS_PUNCH'),
  (19, 'UNBALANCE'),
  (20, 'VACUUM');

/* (optional) seed data; keep or delete as you like */
INSERT OR IGNORE INTO outcome_types (id, name) VALUES
  (1,'HIT'),(2,'MISS'),(3,'PARRY'),(4,'BLOCK'),(5,'EVADE'),(6,'FUMBLE')
ON CONFLICT DO NOTHING;

INSERT OR IGNORE INTO defense_types (id, name) VALUES
  (1,'SHIELD_BLOCK'),(2,'WEAPON_PARRY'),(3,'DODGE'),(4,'AUTO_KD')
ON CONFLICT DO NOTHING;


/* =========================================================
   2.  FACT / EVENT TABLES
   ========================================================= */

-- 2‑a  Combat session (one per hunt / log chunk)
CREATE TABLE combat_sessions (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    character_name TEXT NOT NULL,
    started_at     DATETIME NOT NULL,
    last_event_at  DATETIME NOT NULL,   -- 180‑second timeout tracking
    ended_at       DATETIME
);

-- 2‑b  Creature instances (unique within a session)
CREATE TABLE creature_instances (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id    INTEGER NOT NULL REFERENCES combat_sessions(id),
    exist_id      INTEGER NOT NULL,
    noun          TEXT NOT NULL,
    display_name  TEXT NOT NULL,
    first_seen_at DATETIME NOT NULL,
    last_seen_at  DATETIME,
    UNIQUE (session_id, exist_id)
);

-- 2‑c  Attack events
CREATE TABLE attack_events (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id            INTEGER NOT NULL REFERENCES combat_sessions(id),
  sequence              INTEGER NOT NULL,
  creature_instance_id  INTEGER,
  target_exist_id       INTEGER NOT NULL,
  target_noun           TEXT,
  target_name           TEXT,
  attack_name           TEXT NOT NULL,
  attack_damage         INTEGER,
  attack_crit_type      TEXT,
  attack_crit_location  TEXT,
  attack_crit_rank      INTEGER,
  statuses              TEXT,
  occurred_at           DATETIME NOT NULL,
  raw_line              TEXT,
  FOREIGN KEY (creature_instance_id) REFERENCES creature_instances(id) DEFERRABLE INITIALLY DEFERRED
);
-- timeline index: all activity in a hunt
CREATE INDEX idx_attack_session_time ON attack_events(session_id, sequence);

-- 2‑d  Resolution header (one‑to‑one with attack)
CREATE TABLE attack_resolutions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id      INTEGER NOT NULL REFERENCES combat_sessions(id) ON DELETE CASCADE,
    sequence        INTEGER NOT NULL,
    attack_id       INTEGER REFERENCES attack_events(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    resolution_type INTEGER NOT NULL REFERENCES resolution_types(id),
    result_total    INTEGER,               -- nullable for odd rolls
    d100_roll       INTEGER,
    raw_line        TEXT,
    UNIQUE (attack_id)
);
CREATE INDEX idx_resolutions_session_seq ON attack_resolutions(session_id, sequence);

-- 2‑e  Resolution components (flexible key/value)
CREATE TABLE resolution_components (
    resolution_id    INTEGER REFERENCES attack_resolutions(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    session_id       INTEGER NOT NULL REFERENCES combat_sessions(id),
    sequence         INTEGER NOT NULL,
    component_name   TEXT    NOT NULL,
    component_value  INTEGER NOT NULL,
    PRIMARY KEY (resolution_id, component_name)
);
CREATE INDEX idx_components_session_seq ON resolution_components(session_id, sequence);

-- 2‑f  Defense events (optional row per defensive outcome)
CREATE TABLE defense_events (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    attack_id     INTEGER NOT NULL REFERENCES attack_events(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    defense_type  INTEGER REFERENCES defense_types(id),
    defended_by   TEXT NOT NULL CHECK (defended_by IN ('TARGET','ALLY','ENVIRONMENT')),
    detail        TEXT
);

/*Block defense rows on non-defensive outcomes*/
CREATE TRIGGER defense_outcome_enforce
BEFORE INSERT ON defense_events
FOR EACH ROW
WHEN (
    (SELECT name
        FROM outcome_types
      WHERE id = (
        SELECT outcome_id 
          FROM attack_events 
         WHERE id = NEW.attack_id
      )
    ) NOT IN ('PARRY', 'BLOCK', 'EVADE', 'FUMBLE')
)
BEGIN
  SELECT RAISE(ABORT,
    'Defense row illegal: parent attack is not a defensive outcome');
end;

-- 2‑g  Damage components
CREATE TABLE damage_components (
    id            INTEGER PRIMARY KEY,
    attack_id     INTEGER REFERENCES attack_events(id) ON DELETE CASCADE,
    location_id   INTEGER REFERENCES locations(id),
    damage        INTEGER,
    critical_type INTEGER REFERENCES critical_types(id),
    critical_rank INTEGER,
    damage_type   INTEGER REFERENCES damage_types(id),
    raw_line      TEXT
);
CREATE INDEX idx_damage_components_attack ON damage_components(attack_id);

-- 2‑h  Flare events
CREATE TABLE flare_events (
    id              INTEGER PRIMARY KEY,
    session_id      INTEGER NOT NULL DEFAULT 0,
    attack_sequence INTEGER NOT NULL DEFAULT 0,
    flare_sequence  INTEGER NOT NULL DEFAULT 0,
    flare_name      TEXT NOT NULL,
    target_exist_id INTEGER,
    target_noun     TEXT,
    target_name     TEXT,
    attack_id       INTEGER REFERENCES attack_events(id) ON DELETE CASCADE,
    flare_type      INTEGER REFERENCES flare_types(id),
    location_id     INTEGER REFERENCES locations(id),
    damage          INTEGER,
    critical_type   INTEGER REFERENCES critical_types(id),
    critical_rank   INTEGER,
    note            TEXT,
    raw_line        TEXT
);
CREATE INDEX idx_flare_events_type_location ON flare_events(flare_type, location_id);
CREATE INDEX idx_flares_session_seq ON flare_events(session_id, attack_sequence);

-- 2‑i  Projectile instances (every lodged arrow / bolt / dagger …)
CREATE TABLE projectiles (
    id              INTEGER PRIMARY KEY,
    attack_id       INTEGER   REFERENCES attack_events(id)        ON DELETE CASCADE,
    creature_id     INTEGER   REFERENCES creature_instances(id),
    location_id     INTEGER REFERENCES locations(id),
    lodged_at       DATETIME,
    removed_at      DATETIME,
    fatal_strike    BOOLEAN  DEFAULT FALSE,
    notes           TEXT
);
CREATE INDEX idx_projectiles_creature_loc ON projectiles(creature_id, location_id);
CREATE INDEX idx_projectiles_attack ON projectiles(attack_id);

-- 2‑j  Status events (stuns, webs, arrow‑stuck, buffs …)
CREATE TABLE status_events (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  target_exist_id  INTEGER,
  session_id      INTEGER NOT NULL DEFAULT 0,
  creature_id      INTEGER REFERENCES creature_instances(id),
  applied_by_attack INTEGER REFERENCES attack_events(id),
  status_type      INTEGER REFERENCES status_types(id),
  location_id      INTEGER REFERENCES locations(id),
  started_at       DATETIME NOT NULL,
  ended_at         DATETIME,
  is_active        BOOLEAN GENERATED ALWAYS AS (ended_at IS NULL) STORED,
  notes            TEXT
);
CREATE INDEX idx_status_events_started ON status_events(started_at);
CREATE INDEX idx_status_events_creature_status ON status_events(creature_id, status_type);

COMMIT;
